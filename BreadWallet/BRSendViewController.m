//
//  BRSendViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BRSendViewController.h"
#import "BRRootViewController.h"
#import "BRAmountViewController.h"
#import "BRWalletManager.h"
#import "BRWallet.h"
#import "BRPeerManager.h"
#import "BRPaymentRequest.h"
#import "BRPaymentProtocol.h"
#import "BRKey.h"
#import "BRTransaction.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import <AVFoundation/AVFoundation.h>

//#define BT_CONNECT_TIMEOUT 5.0

#define SCAN_TIP      @"Scan someone else's QR code to get their bitcoin address. "\
"You can send a payment to anyone with an address."
#define CLIPBOARD_TIP @"Bitcoin addresses can also be copied to the clipboard. "\
"A bitcoin address always starts with '1'."
#define PAGE_TIP      @"Tap or swipe right to receive money."

@interface BRSendViewController ()

//@property (nonatomic, strong) GKSession *session;
@property (nonatomic, strong) NSString *addressInWallet, *txName, *txMemo;
@property (nonatomic, assign) BOOL txSecure, clearClipboard;
@property (nonatomic, strong) id urlObserver, fileObserver;
@property (nonatomic, strong) BRTransaction *sweepTx, *tx, *txWithFee;
@property (nonatomic, strong) BRPaymentProtocolRequest *protocolRequest;
@property (nonatomic, strong) ZBarReaderViewController *zbarController;
//@property (nonatomic, strong) BRBubbleView *tipView;

@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *buttons;

@end

@implementation BRSendViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    //TODO: add a field for manually entering a payment address
    //TODO: make title use dynamic font size
    //BUG: clipboard button title is offcenter (ios7 specific font layout bug?)

    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            NSURL *url = note.userInfo[@"url"];
            
            if ([url.scheme isEqual:@"bitcoin"]) {
                [self confirmRequest:[BRPaymentRequest requestWithURL:url]];
                return;
            }

            [[[UIAlertView alloc] initWithTitle:@"unsupported url" message:url.absoluteString delegate:nil
             cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
            [self reset:nil];
        }];

    self.fileObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRFileNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            NSData *file = note.userInfo[@"file"];
            BRPaymentProtocolRequest *request = [BRPaymentProtocolRequest requestWithData:file];
            
            if (request) {
                [self confirmProtocolRequest:request];
                return;
            }

            // TODO: reject payments that don't match requested amounts/scripts, implement refunds
            BRPaymentProtocolPayment *payment = [BRPaymentProtocolPayment paymentWithData:file];
            
            if (payment.transactions.count > 0) {
                for (BRTransaction *tx in payment.transactions) {
//                    [self startSpinner];
                    
                    [[BRPeerManager sharedInstance] publishTransaction:tx completion:^(NSError *error) {
//                        [self stopSpinner];
                        
                        if (error) {
                            [[[UIAlertView alloc] initWithTitle:@"couldn't transmit payment to bitcoin network"
                              message:error.localizedDescription delegate:nil cancelButtonTitle:@"ok"
                              otherButtonTitles:nil] show];
                        }

//                        [self.view addSubview:[[[BRBubbleView
//                         viewWithText:(payment.memo.length > 0 ? payment.memo : @"recieved")
//                         center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] fadeIn]
//                         fadeOutAfterDelay:(payment.memo.length > 10 ? 3.0 : 2.0)]];
                    }];
                }

                return;
            }
            
            BRPaymentProtocolACK *ack = [BRPaymentProtocolACK ackWithData:file];
            
            if (ack) {
//                if (ack.memo.length > 0) {
//                    [self.view addSubview:[[[BRBubbleView viewWithText:ack.memo
//                                             center:CGPointMake(self.view.bounds.size.width/2,
//                                                                self.view.bounds.size.height/2)]
//                                            fadeIn] fadeOutAfterDelay:2.0]];
//                }

                return;
            }
            
            [[[UIAlertView alloc] initWithTitle:@"unsupported or corrupted document" message:nil delegate:nil
              cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
        }];

}

- (void)dealloc
{
    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.fileObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.fileObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self cancel:nil];

    //    self.session = [[GKSession alloc] initWithSessionID:GK_SESSION_ID
    //                    displayName:[UIDevice.currentDevice.name stringByAppendingString:@" Wallet"]
    //                    sessionMode:GKSessionModeClient];
    //    self.session.delegate = self;
    //    [self.session setDataReceiveHandler:self withContext:nil];
    //    self.session.available = YES;
}

- (void)viewDidAppear:(BOOL)animated
{
    [self zbarController]; // pre-load zbarController
}

- (void)viewWillDisappear:(BOOL)animated
{
    //    self.session.available = NO;
    //    [self.session disconnectFromAllPeers];
    //    self.session = nil;

    [self hideTips];

    [super viewWillDisappear:animated];
}

- (ZBarReaderViewController *)zbarController
{
    if (! _zbarController) {
        _zbarController = [ZBarReaderViewController new];
        _zbarController.readerDelegate = self;
        _zbarController.cameraOverlayView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"cameraguide.png"]];
        _zbarController.cameraOverlayView.center = CGPointMake(_zbarController.view.center.x,
                                                               _zbarController.view.center.y - 10.0);
        _zbarController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        //TODO: XXXX custom transition so it appears to cover from above
    }

    return _zbarController;
}

- (void)confirmTransaction:(BRTransaction *)tx name:(NSString *)name memo:(NSString *)memo isSecure:(BOOL)isSecure
{
    if (! tx) {
        [self cancel:nil];
        return;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];
    uint64_t txAmount = [m.wallet amountSentByTransaction:tx] - [m.wallet amountReceivedFromTransaction:tx];
    NSString *amount = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:txAmount],
                        [m localCurrencyStringForAmount:txAmount]];
    NSString *msg = @"";//(isSecure && name.length > 0) ? LOCK NOEMOJI @" " : @"";

    //if (! isSecure && self.protocolRequest.errorMessage.length > 0) msg = [msg stringByAppendingString:REDX @" "];
    if (name.length > 0) msg = [msg stringByAppendingString:name];
    if (! isSecure && msg.length > 0) msg = [msg stringByAppendingString:@"\n"];
    if (! isSecure || msg.length == 0) msg = [msg stringByAppendingString:[m.wallet addressForTransaction:tx]];
    if (memo.length > 0) msg = [[msg stringByAppendingString:@"\n"] stringByAppendingString:memo];

    [[[UIAlertView alloc] initWithTitle:@"confirm payment" message:msg delegate:self cancelButtonTitle:@"cancel"
                      otherButtonTitles:amount, nil] show];
}

- (void)confirmRequest:(BRPaymentRequest *)request
{
    if (! [request isValid]) {
        if ([request.paymentAddress isValidBitcoinPrivateKey] || [request.paymentAddress isValidBitcoinBIP38Key]) {
            [self confirmSweep:request.paymentAddress];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:@"not a valid bitcoin address" message:request.paymentAddress
                                       delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
            [self cancel:nil];
        }

        return;
    }

    if (request.r.length > 0) { // payment protocol over HTTP
//        [self startSpinner];

        [BRPaymentRequest fetch:request.r completion:^(BRPaymentProtocolRequest *req, NSError *error) {
//            [self stopSpinner];

            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:error.localizedDescription
                                           delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
                [self cancel:nil];
            }
            else [self confirmProtocolRequest:req];
        }];

        return;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];

    if ([m.wallet containsAddress:request.paymentAddress]) {
        [[[UIAlertView alloc] initWithTitle:nil message:@"this payment address is already in your wallet" delegate:nil
                          cancelButtonTitle:@"ok" otherButtonTitles:nil] show];

        self.addressInWallet = request.paymentAddress;
        [self cancel:nil];
    }
    else if (request.amount == 0) {
        BRAmountViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"AmountViewController"];

        c.delegate = self;
        c.request = request;
        c.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [m stringForAmount:m.wallet.balance],
                                  [m localCurrencyStringForAmount:m.wallet.balance]];
        [self.navigationController pushViewController:c animated:YES];
    }
    else if (request.amount < TX_MIN_OUTPUT_AMOUNT) {
        [[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:[@"bitcoin payments can't be less than "
          stringByAppendingString:[m stringForAmount:TX_MIN_OUTPUT_AMOUNT]] delegate:nil cancelButtonTitle:@"ok"
          otherButtonTitles:nil] show];
        [self cancel:nil];
    }
    else {
        self.tx = [m.wallet transactionFor:request.amount to:request.paymentAddress withFee:NO];
        self.txWithFee = [m.wallet transactionFor:request.amount to:request.paymentAddress withFee:YES];

        if (! self.tx) {
            [[[UIAlertView alloc] initWithTitle:@"insufficient funds" message:nil delegate:nil cancelButtonTitle:@"ok"
                              otherButtonTitles:nil] show];
            [self cancel:nil];
        }

        [self confirmTransaction:self.tx name:request.label memo:request.message isSecure:NO];
    }
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)request
{
    BOOL valid = [request isValid];

    if (! valid && [request.errorMessage isEqual:@"request expired"]) {
        [[[UIAlertView alloc] initWithTitle:@"bad payment request" message:request.errorMessage delegate:nil
                          cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    BRWalletManager *m = [BRWalletManager sharedInstance];

    self.tx = [m.wallet transactionForAmounts:request.details.outputAmounts
                              toOutputScripts:request.details.outputScripts withFee:NO];
    self.txWithFee = [m.wallet transactionForAmounts:request.details.outputAmounts
                                     toOutputScripts:request.details.outputScripts withFee:YES];
    self.protocolRequest = request;

    if (! self.tx) {
        [[[UIAlertView alloc] initWithTitle:@"insufficient funds" message:nil delegate:nil cancelButtonTitle:@"ok"
                          otherButtonTitles:nil] show];
        [self cancel:nil];
    }

    [self confirmTransaction:self.tx name:request.commonName memo:request.details.memo
                    isSecure:(valid && ! [request.pkiType isEqual:@"none"]) ? YES : NO];
}

- (void)confirmSweep:(NSString *)privKey
{
    if (! [privKey isValidBitcoinPrivateKey] && ! [privKey isValidBitcoinBIP38Key]) return;

    BRWalletManager *m = [BRWalletManager sharedInstance];
//    BRBubbleView *v = [BRBubbleView viewWithText:@"checking private key balance..."
//                                          center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
//
//    v.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
//    v.customView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
//    [(id)v.customView startAnimating];
//    [self.view addSubview:[v fadeIn]];

    [m sweepPrivateKey:privKey withFee:YES completion:^(BRTransaction *tx, NSError *error) {
//        [v fadeOut];

        if (error) {
            [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:self
                              cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
            [self cancel:nil];
        }
        else if (tx) {
            uint64_t fee = tx.standardFee, amount = fee;

            for (NSNumber *amt in tx.outputAmounts) {
                amount += amt.unsignedLongLongValue;
            }

            self.sweepTx = tx;

            [[[UIAlertView alloc] initWithTitle:nil
              message:[NSString stringWithFormat:@"Send %@ (%@) from this private key into your wallet? "
              "The bitcoin network will receive a fee of %@ (%@).", [m stringForAmount:amount],
              [m localCurrencyStringForAmount:amount], [m stringForAmount:fee], [m localCurrencyStringForAmount:fee]]
              delegate:self cancelButtonTitle:@"cancel" otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)",
              [m stringForAmount:amount], [m localCurrencyStringForAmount:amount]], nil] show];
        }
        else [self cancel:nil];
    }];
}

- (BOOL)hideTips
{
//    if (self.tipView.alpha < 0.5) return NO;
//    [self.tipView fadeOut];
    return YES;
}

//- (BOOL)nextTip
//{
//    BRBubbleView *v = self.tipView;
//
//    if (v.alpha < 0.5) return NO;
//
//    if ([v.text isEqual:SCAN_TIP]) {
//        UIButton *b = self.requestButtons[[self.requestIDs indexOfObject:CLIPBOARD_ID]];
//
//        self.tipView = [BRBubbleView viewWithText:CLIPBOARD_TIP tipPoint:CGPointMake(b.center.x, b.center.y + 5.0)
//                                     tipDirection:BRBubbleTipDirectionUp];
//    }
//    else if ([v.text isEqual:CLIPBOARD_TIP]) {
//        self.tipView = [BRBubbleView viewWithText:PAGE_TIP
//                                         tipPoint:CGPointMake(self.view.bounds.size.width/2.0, self.view.superview.bounds.size.height)
//                                     tipDirection:BRBubbleTipDirectionDown];
//    }
//    else self.tipView = nil;
//
//    self.tipView.backgroundColor = v.backgroundColor;
//    self.tipView.font = v.font;
//    if (self.tipView) [self.view addSubview:[self.tipView fadeIn]];
//    [v fadeOut];
//
//    return YES;
//}

#pragma mark - IBAction

- (IBAction)swipeLeft:(id)sender
{
    // the following is a hack to avoid triggering a crash bug in UIQueuingScrollView described here:
    // http://stackoverflow.com/questions/19939030/how-to-solve-failed-to-determine-navigation-direction-for-scroll-bug
    // we do the animated scroll manually and call pageviewcontroller setviewcontrollers without animation afterward

    for (UIView *view in self.parentViewController.view.subviews) {
        if (! [view isKindOfClass:[UIScrollView class]]) continue;
        [(id)view setContentOffset:CGPointMake([(id)view contentOffset].x + view.frame.size.width,
                                               [(id)view contentOffset].y) animated:YES];
        break;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [(id)self.parentViewController
         setViewControllers:@[[(id)self.parentViewController.parentViewController receiveViewController]]
         direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    });
}

//- (IBAction)info:(id)sender
//{
//    if ([self nextTip]) return;
//
//    UIButton *b = self.requestButtons[[self.requestIDs indexOfObject:QR_ID]];
//
//    self.tipView = [BRBubbleView viewWithText:SCAN_TIP tipPoint:CGPointMake(b.center.x, b.center.y - 5.0)
//                                 tipDirection:BRBubbleTipDirectionDown];
//    self.tipView.backgroundColor = [UIColor orangeColor];
//    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
//    [self.view addSubview:[self.tipView fadeIn]];
//}
//
//- (IBAction)next:(id)sender
//{
//    [self nextTip];
//}

- (IBAction)scanQR:(id)sender
{
    [sender setEnabled:NO];

    [self.navigationController presentViewController:self.zbarController animated:YES completion:^{
        NSLog(@"present qr reader complete");
    }];

    BOOL hasFlash = [[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] hasTorch];
    UIBarButtonItem *flashButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"flash.png"]
                                    style:UIBarButtonItemStylePlain target:self action:@selector(flash:)];

    // replace zbarController.view info button with flash toggle
    for (UIView *v in self.zbarController.view.subviews) {
        for (id t in v.subviews) {
            if ([t isKindOfClass:[UIToolbar class]] && [[t items] count] > 1) {
                UIBarButtonItem *cancelButton =
                    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                     target:[(UIBarButtonItem *)[t items][0] target] action:[(UIBarButtonItem *)[t items][0] action]];

                [t setItems:hasFlash ? @[cancelButton, [t items][1], flashButton] : @[cancelButton, [t items][1]]];
            }
        }
    }
}

- (IBAction)payToClipboard:(id)sender
{
    NSString *s = [[[UIPasteboard generalPasteboard] string]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];

    [sender setEnabled:NO];
    self.clearClipboard = YES;

    if (! [req isValid] && ! [s isValidBitcoinPrivateKey] && ! [s isValidBitcoinBIP38Key]) {
        [[[UIAlertView alloc] initWithTitle:@"clipboard doesn't contain a valid bitcoin address" message:nil
          delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
        [self cancel:nil];
    }
    else [self confirmRequest:req];
}

- (IBAction)reset:(id)sender
{
    if (self.navigationController.topViewController != self.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }

    if (self.clearClipboard) [[UIPasteboard generalPasteboard] setString:@""];
    [self cancel:sender];
}

- (IBAction)cancel:(id)sender
{
    self.tx = self.txWithFee = self.sweepTx = nil;
    self.protocolRequest = nil;
    self.txName = self.txMemo = nil;
    self.txSecure = self.clearClipboard = NO;

    for (UIButton *button in self.buttons) {
        button.enabled = YES;
    }
}

- (IBAction)flash:(id)sender
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

    device.torchMode = device.torchActive ? AVCaptureTorchModeOff : AVCaptureTorchModeOn;
}

#pragma mark - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    amountViewController.request.amount = amount;
    [self confirmRequest:amountViewController.request];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)reader didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    // ignore additonal qr codes while we're still giving visual feedback about the current one
    if ([[(id)self.zbarController.cameraOverlayView image] isEqual:[UIImage imageNamed:@"cameraguide-green.png"]]) {
        return;
    }

    for (id result in info[ZBarReaderControllerResults]) {
        NSString *s = (id)[result data];
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:s];

        if (! [request isValid] && ! [s isValidBitcoinPrivateKey] && ! [s isValidBitcoinBIP38Key]) {
            [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide-red.png"]];

            // display red camera guide for 0.5 seconds
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide.png"]];

                if ([s hasPrefix:@"bitcoin:"] || [request.paymentAddress hasPrefix:@"1"]) {
                    [[[UIAlertView alloc] initWithTitle:@"not a valid bitcoin address"
                      message:request.paymentAddress delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
                }
                else {
                    [[[UIAlertView alloc] initWithTitle:@"not a bitcoin QR code" message:nil delegate:nil
                      cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
                }
            });
        }
        else {
            [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide-green.png"]];

            if (request.r.length > 0) { // start fetching payment protocol request right away
                [BRPaymentRequest fetch:request.r completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                    if (error) {
                        [[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:error.localizedDescription
                          delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
                        [self cancel:nil];
                        return;
                    }

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [reader dismissViewControllerAnimated:YES completion:^{
                            [(id)self.zbarController.cameraOverlayView
                             setImage:[UIImage imageNamed:@"cameraguide.png"]];
                        }];

                        [self confirmProtocolRequest:req];
                    });
                }];
            }
            else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [reader dismissViewControllerAnimated:YES completion:^{
                        [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide.png"]];
                    }];

                    [self confirmRequest:request];
                });
            }
        }

        break;
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self cancel:nil];
        return;
    }

    if (self.sweepTx) {
//        [self startSpinner];

        [[BRPeerManager sharedInstance] publishTransaction:self.sweepTx completion:^(NSError *error) {
//            [self stopSpinner];

            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"couldn't sweep balance" message:error.localizedDescription
                  delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
                [self cancel:nil];
                return;
            }

//            [self.view addSubview:[[[BRBubbleView viewWithText:@"swept!"
//                                    center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
//                                    fadeIn] fadeOutAfterDelay:2.0]];
            [self reset:nil];
        }];

        return;
    }
    else if (! self.tx) return;

    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRPaymentProtocolRequest *request = self.protocolRequest;
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    uint32_t freeHeight = [m.wallet blockHeightUntilFree:self.tx];

    if ([title hasPrefix:@"+ "] || [title isEqual:@"no fee"]) {
        if ([title hasPrefix:@"+ "]) self.tx = self.txWithFee;

        if (! self.tx) {
            [[[UIAlertView alloc] initWithTitle:@"insufficient funds" message:nil delegate:nil cancelButtonTitle:@"ok"
                              otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }
    }
    else if (self.tx != self.txWithFee && freeHeight > [[BRPeerManager sharedInstance] lastBlockHeight] + 1) {
        uint64_t txFee = self.txWithFee ? [m.wallet feeForTransaction:self.txWithFee] : self.tx.standardFee;
        NSString *fee = [m stringForAmount:txFee];
        NSString *localCurrencyFee = [m localCurrencyStringForAmount:txFee];

        //if (freeHeight != TX_UNCONFIRMED) {
        //    NSTimeInterval t = (freeHeight - [[BRPeerManager sharedInstance] lastBlockHeight])*600;
        //    int minutes = t/60, hours = t/(60*60), days = t/(60*60*24);
        //    NSString *time = [NSString stringWithFormat:@"%d %@%@", days ? days : (hours ? hours : minutes),
        //                      days ? @"day" : (hours ? @"hour" : @"minutes"),
        //                      days > 1 ? @"s" : (days == 0 && hours > 1 ? @"s" : @"")];
        //
        //    [[[UIAlertView alloc]
        //      initWithTitle:[NSString stringWithFormat:@"%@ (%@) transaction fee recommended", fee, localCurrencyFee]
        //      message:[NSString stringWithFormat:@"estimated confirmation time with no fee: %@", time] delegate:self
        //      cancelButtonTitle:nil otherButtonTitles:@"no fee",
        //      [NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
        //    return;
        //}

        [[[UIAlertView alloc] initWithTitle:nil
          message:[NSString stringWithFormat:@"the bitcoin network will receive a fee of %@ (%@)", fee,
          localCurrencyFee] delegate:self cancelButtonTitle:@"cancel"
          otherButtonTitles:[NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
        return;
    }

    //TODO: check for duplicate transactions

    NSLog(@"signing transaction");
    [m.wallet signTransaction:self.tx];

    if (! [self.tx isSigned]) {
        [[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:@"error signing bitcoin transaction"
          delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
        [self cancel:nil];
        return;
    }

    NSLog(@"signed transaction:\n%@", [NSString hexWithData:self.tx.data]);

//    [self startSpinner];

    [[BRPeerManager sharedInstance] publishTransaction:self.tx completion:^(NSError *error) {
        if (request.details.paymentURL.length > 0) return;
//        [self stopSpinner];

        if (error) {
            [[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:error.localizedDescription
              delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
            [self cancel:nil];
            return;
        }

//        [self.view addSubview:[[[BRBubbleView viewWithText:@"sent!"
//                                 center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
//                                fadeIn] fadeOutAfterDelay:2.0]];
        [self reset:nil];
    }];

    if (request.details.paymentURL.length > 0) {
        uint64_t refundAmount = 0;
        NSMutableData *refundScript = [NSMutableData data];

        // use the payment transaction's change address as the refund address
        [refundScript appendScriptPubKeyForAddress:m.wallet.changeAddress];

        for (NSNumber *amount in request.details.outputAmounts) {
            refundAmount += [amount unsignedLongLongValue];
        }

        // TODO: XXXX keep track of commonName/memo to associate them with outputScripts
        BRPaymentProtocolPayment *payment =
            [[BRPaymentProtocolPayment alloc] initWithMerchantData:request.details.merchantData
             transactions:@[self.tx] refundToAmounts:@[@(refundAmount)] refundToScripts:@[refundScript] memo:nil];
        
        [BRPaymentRequest postPayment:payment to:request.details.paymentURL
        completion:^(BRPaymentProtocolACK *ack, NSError *error) {
//            [self stopSpinner];
            
            if (error && ! [m.wallet transactionIsRegistered:self.tx.txHash]) {
                [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:nil
                  cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
                [self cancel:nil];
                return;
            }
            
//          [self.view addSubview:[[[BRBubbleView viewWithText:(ack.memo.length > 0 ? ack.memo : @"sent!")
//                                   center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
//                                  fadeIn] fadeOutAfterDelay:(ack.memo.length > 10 ? 3.0 : 2.0)]];
            [self reset:nil];
            
            if (error) { // transaction was sent despite payment protocol error
                [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:nil
                  cancelButtonTitle:@"ok" otherButtonTitles:nil] performSelector:@selector(show) withObject:nil
                 afterDelay:2.0];
            }
        }];
    }
//    else {
//        NSLog(@"sending signed request to %@", self.requestIDs[self.selectedIndex]);
//
//        NSError *error = nil;
//
//        [self.session sendData:[[tx toHex] dataUsingEncoding:NSUTF8StringEncoding]
//         toPeers:@[self.requestIDs[self.selectedIndex]] withDataMode:GKSendDataReliable error:&error];
//
//        if (error) {
//            [[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:error.localizedDescription
//             delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
//        }
//
//        [self.requestIDs removeObjectAtIndex:self.selectedIndex];
//        [self.requests removeObjectAtIndex:self.selectedIndex];
//    }
}

//#pragma mark - GKSessionDelegate
//
//// Indicates a state change for the given peer.
//- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
//{
//    NSLog(@"%@ didChangeState:%@", peerID, state == GKPeerStateAvailable ? @"available" :
//          state == GKPeerStateUnavailable ? @"unavailable" :
//          state == GKPeerStateConnecting ? @"connecting" :
//          state == GKPeerStateConnected ? @"connected" :
//          state == GKPeerStateDisconnected ? @"disconnected" : @"unkown");
//    
//    if (state == GKPeerStateAvailable) {
//        if (! [self.requestIDs containsObject:peerID]) {
//            [self.requestIDs addObject:peerID];
//            [self.requests addObject:[BRPaymentRequest new]];
//            
//            [session connectToPeer:peerID withTimeout:BT_CONNECT_TIMEOUT];
//            
//            [self layoutButtonsAnimated:YES];
//        }
//    }
//    else if (state == GKPeerStateUnavailable || state == GKPeerStateDisconnected) {
//        if ([self.requestIDs containsObject:peerID]) {
//            NSUInteger idx = [self.requestIDs indexOfObject:peerID];
//            
//            [self.requestIDs removeObjectAtIndex:idx];
//            [self.requests removeObjectAtIndex:idx];
//            [self layoutButtonsAnimated:YES];
//        }
//    }
//}
//
//// Indicates a connection request was received from another peer.
////
//// Accept by calling -acceptConnectionFromPeer:
//// Deny by calling -denyConnectionFromPeer:
//- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
//{
//    NSAssert(FALSE, @"%s:%d %s: received connection request (not in client mode)", __FILE__, __LINE__,  __func__);
//    return;
//    
//    
//    [session denyConnectionFromPeer:peerID];
//}
//
//// Indicates a connection error occurred with a peer, including connection request failures or timeouts.
//- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
//{
//    [[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:error.localizedDescription delegate:nil
//                      cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
//    
//    if (self.selectedIndex != NSNotFound && [self.requestIDs[self.selectedIndex] isEqual:peerID]) {
//        self.selectedIndex = NSNotFound;
//    }
//    
//    if ([self.requestIDs containsObject:peerID]) {
//        NSUInteger idx = [self.requestIDs indexOfObject:peerID];
//        
//        [self.requestIDs removeObjectAtIndex:idx];
//        [self.requests removeObjectAtIndex:idx];
//        [self layoutButtonsAnimated:YES];
//    }
//}
//
//// Indicates an error occurred with the session such as failing to make available.
//- (void)session:(GKSession *)session didFailWithError:(NSError *)error
//{
//    if (self.selectedIndex != NSNotFound && ! [self.requestIDs[self.selectedIndex] isEqual:CLIPBOARD_ID] &&
//        ! [self.requestIDs[self.selectedIndex] isEqual:QR_ID]) {
//        self.selectedIndex = NSNotFound;
//    }
//    
//    NSIndexSet *indexes =
//        [self.requestIDs indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
//            return ! [obj isEqual:CLIPBOARD_ID] && ! [obj isEqual:QR_ID];
//        }];
//    
//    [self.requestIDs removeObjectsAtIndexes:indexes];
//    [self.requests removeObjectsAtIndexes:indexes];
//    
//    [self layoutButtonsAnimated:YES];
//    
//    //[[[UIAlertView alloc] initWithTitle:@"couldn't make payment" message:error.localizedDescription delegate:nil
//    //                  cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
//}
//
//- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
//{
//    NSUInteger idx = [self.requestIDs indexOfObject:peer];
//    
//    if (idx == NSNotFound) {
//        NSAssert(FALSE, @"%s:%d %s: idx = NSNotFound", __FILE__, __LINE__,  __func__);
//        return;
//    }
//    
//    BRPaymentRequest *req = self.requests[idx];
//    
//    [req setData:data];
//    
//    if (! req.valid) {
//        [[[UIAlertView alloc] initWithTitle:@"couldn't validate payment request"
//          message:@"The payment reqeust did not contain a valid merchant signature" delegate:self
//          cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
//        
//        if (self.selectedIndex == idx) {
//            self.selectedIndex = NSNotFound;
//        }
//        
//        [self.requestIDs removeObjectAtIndex:idx];
//        [self.requests removeObjectAtIndex:idx];
//        [self layoutButtonsAnimated:YES];
//        
//        return;
//    }
//    
//    NSLog(@"got payment reqeust for %@", peer);
//    NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//    
//    if (self.selectedIndex == idx) [self confirmRequest:req];
//}

@end