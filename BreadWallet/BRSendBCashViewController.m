//
//  BRSendBCashViewController.m
//  BreadWallet
//
//  Created by Adrian Corscadden on 2017-08-07.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

#import "BRSendBCashViewController.h"
#import "BRScanViewController.h"
#import "BRWalletManager.h"
#import "BRWallet.h"
#import "breadwallet-Swift.h"
#import "BRPaymentRequest.h"

NSString * const bCashTxHashKey = @"BCashTxHashKey";

@interface BRSendBCashViewController ()

@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UIButton *scan;
@property (nonatomic, strong) UIButton *paste;
@property (nonatomic, strong) BRScanViewController *scanController;
@property (nonatomic, strong) UILabel *txHashHeader;
@property (nonatomic, strong) UIButton *txHashButton;
@property (nonatomic, strong) NSString *address;

@end

@implementation BRSendBCashViewController 

- (void)viewDidLoad
{
    [self addSubviews];
    [self addConstraints];
    [self setInitialData];
}

- (void)addSubviews
{
    self.body = [[UILabel alloc] init];
    self.scan = [self buttonWithTitle:@"scan QR code" imageNamed:@"cameraguide-blue-small"];
    self.paste = [self buttonWithTitle:@"pay address from clipboard" imageNamed:nil];
    self.txHashHeader = [[UILabel alloc] init];
    self.txHashButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.view addSubview:self.body];
    [self.view addSubview:self.scan];
    [self.view addSubview:self.paste];
    [self.view addSubview:self.body];
    [self.view addSubview:self.txHashHeader];
    [self.view addSubview:self.txHashButton];
}

- (void)addConstraints
{
    [self constrain:@[
                      [self constraintFrom:self.body toView:self.view attribute:NSLayoutAttributeLeading constant:16.0],
                      [NSLayoutConstraint constraintWithItem:self.body attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom multiplier:1.0 constant:16.0],
                      [self constraintFrom:self.body toView:self.view attribute:NSLayoutAttributeTrailing constant:-16.0], ]];

    [self constrain:@[
                      [self constraintFrom:self.scan toView:self.view attribute:NSLayoutAttributeCenterX constant:0.0],
                      [self constraintFrom:self.scan toView:self.view attribute:NSLayoutAttributeCenterY constant:-35.0],
                      [self constrain:self.scan toWidth:290.0],
                      [self constrain:self.scan toHeight:44.0] ]];

    [self constrain:@[
                      [self constraintFrom:self.paste toView:self.view attribute:NSLayoutAttributeCenterX constant:0.0],
                      [self constraintFrom:self.paste toView:self.view attribute:NSLayoutAttributeCenterY constant:35.0],
                      [self constrain:self.paste toWidth:290.0],
                      [self constrain:self.paste toHeight:44.0] ]];

    [self constrain:@[
                      [self constraintFrom:self.txHashHeader toView:self.view attribute:NSLayoutAttributeLeading constant:16.0],
                      [NSLayoutConstraint constraintWithItem:self.txHashHeader attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.paste attribute:NSLayoutAttributeBottom multiplier:1.0 constant:40.0]
                      ]];

    [self constrain:@[
                      [self constraintFrom:self.txHashButton toView:self.view attribute:NSLayoutAttributeLeading constant:16.0],
                      [NSLayoutConstraint constraintWithItem:self.txHashButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.txHashHeader attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]
                      ]];
}

- (void)setInitialData
{
    self.view.backgroundColor = [UIColor clearColor];
    self.navigationItem.title = @"Withdraw Bitcoin Cash";

    self.body.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:17.0];
    self.body.numberOfLines = 0;
    self.body.lineBreakMode = NSLineBreakByWordWrapping;
    self.body.text = @"Use one of the options below to enter your destination address. All Bitcoin Cash in your wallet at the time of the fork will be sent.";
    self.body.translatesAutoresizingMaskIntoConstraints = NO;

    [self.scan setImageEdgeInsets:UIEdgeInsetsMake(0, -10.0, 0.0, 10.0)];
    [self.scan addTarget:self action:@selector(didTapScan) forControlEvents:UIControlEventTouchUpInside];
    [self.paste addTarget:self action:@selector(didTapPaste) forControlEvents:UIControlEventTouchUpInside];

    self.txHashHeader.translatesAutoresizingMaskIntoConstraints = NO;
    self.txHashHeader.text = @"Bitcoin Cash Withraw Transaction ID";
    [self.txHashHeader setHidden:YES];
    self.txHashButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self setTxHashData];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (! self.scanController) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:[NSBundle mainBundle]];
        self.scanController = [storyboard instantiateViewControllerWithIdentifier:@"ScanViewController"];
        self.scanController.delegate = self;
    }
}

- (void)setTxHashData
{
    NSString *txHash = [[NSUserDefaults standardUserDefaults] stringForKey:bCashTxHashKey];
    if (txHash) {
        [self.txHashButton setTitle:txHash forState:UIControlStateNormal];
        [self.txHashHeader setHidden:NO];
    }
}


- (void)didTapScan
{
    [self.navigationController presentViewController:self.scanController animated:YES completion:nil];
}

- (void)didTapPaste
{
    NSString *str = [[UIPasteboard generalPasteboard].string
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (str) {
        self.address = str;
        [self confirmSend];
    } else {
        [self showErrorMessage:@"No Address on Pasteboard"];
    }
}

- (void)confirmSend
{
    NSString *message = [NSString stringWithFormat:@"Would you like to send your entire BCH balance to %@", self.address];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Send BCH?" message:message delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"OK", nil];
    [alert show];
}

- (void)showErrorMessage:(NSString *)message
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
}

- (void)send
{
    BCashSender *sender = [[BCashSender alloc] init];
    [sender sendBCashTransactionWithWalletManager:[BRWalletManager sharedInstance]
                                          address:self.address
                                         feePerKb:MIN_FEE_PER_KB
                                         callback:^(NSString * _Nullable errorMessage) {
        if (errorMessage) {
            NSLog(@"Error: %@", errorMessage);
        } else {
            NSLog(@"BCash Success");
        }
    }];
}

#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) {
        [self send];
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection
{
    for (AVMetadataMachineReadableCodeObject *codeObject in metadataObjects) {
        if (! [codeObject.type isEqual:AVMetadataObjectTypeQRCode]) continue;
        NSString *addr = [codeObject.stringValue stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:addr];
        if ((request.isValid && [request.scheme isEqual:@"bitcoin"]) || [addr isValidBitcoinPrivateKey] ||
                   [addr isValidBitcoinBIP38Key]) {
            if (request.r.length == 0) {
                self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
                [self.scanController stop];
                [self.scanController dismissViewControllerAnimated:YES completion:^{
                    [self resetQRGuide];
                    self.address = request.paymentAddress;
                    [self confirmSend];
                }];
            }
        }
        
        break;
    }
}

- (void)resetQRGuide
{
    self.scanController.message.text = nil;
    self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide"];
}

#pragma mark AutoLayout Helpers
- (void)constrain:(NSArray<NSLayoutConstraint *>*)constraints
{
    [NSLayoutConstraint activateConstraints:constraints];
}

- (NSLayoutConstraint* )constrain:(UIView*)view toWidth:(CGFloat)width
{
    return [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:width];
}

- (NSLayoutConstraint* )constrain:(UIView*)view toHeight:(CGFloat)width
{
    return [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:width];
}

- (NSLayoutConstraint *)constraintFrom:(UIView *)fromView toView:(UIView*)toView attribute:(NSLayoutAttribute)attribute constant:(CGFloat)constant
{
    return [NSLayoutConstraint constraintWithItem:fromView attribute:attribute relatedBy:NSLayoutRelationEqual toItem:toView attribute:attribute multiplier:1.0 constant:constant];
}

- (UIButton *)buttonWithTitle:(NSString *)title imageNamed:(NSString *)imageName
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
    [button setBackgroundImage:[UIImage imageNamed:@"button-bg-blue"] forState:UIControlStateNormal];
    [button setBackgroundImage:[UIImage imageNamed:@"button-bg-blue-pressed"] forState:UIControlStateHighlighted];
    [button setTitleColor:[UIColor colorWithRed:0.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitleColor:[UIColor colorWithRed:0.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

@end
