//
//  BCashSender.swift
//  BreadWallet
//
//  Created by Adrian Corscadden on 2017-08-08.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

import Foundation
import BRCore

typealias BRTxRef = UnsafeMutablePointer<BRCore.BRTransaction>

private let apiClient = BRAPIClient()

@objc class BCashSender : NSObject {

    func sendBCashTransaction(walletManager: BRWalletManager, address: String, feePerKb: UInt64, callback: @escaping (String?) -> Void) {
        let genericError = "Something went wrong";
        guard let txData = walletManager.wallet?.bCashSweepTx(to: address, feePerKb: feePerKb)?.data else { assert(false, "No Tx Data"); return callback(genericError) }
        guard let txCount = walletManager.wallet?.allTransactions.count else { assert(false, "Could not get txCount"); return callback(genericError) }
        guard let mpk = walletManager.masterPublicKey?.masterPubKey else { assert(false, "Count not get mpkData"); return callback(genericError) }

        let tx: BRTxRef = txData.withUnsafeBytes({ (ptr: UnsafePointer<UInt8>) -> BRTxRef in
            return BRTransactionParse(ptr, MemoryLayout<BRCore.BRTransaction>.stride)
        })
        defer { BRTransactionFree(tx) }
        let wallet = BRWalletNew(nil, txCount, mpk)
        defer { BRWalletFree(wallet) }
        BRWalletUnusedAddrs(wallet, nil, UInt32(txCount), 0)
        BRWalletUnusedAddrs(wallet, nil, UInt32(txCount), 1)

        //TODO - use real amount here
        guard let seedData = walletManager.seed(withPrompt: "Authorize sending BCH Balance", forAmount: 0) else {
            return callback(genericError)
        }
        var seed: BRCore.UInt512 = seedData.withUnsafeBytes { $0.pointee }
        BRWalletSignTransaction(wallet, tx, 0x40, &seed, MemoryLayout<BRCore.UInt512>.stride)

        apiClient.publishBCashTransaction(txData: Data(bytes: tx, count: MemoryLayout<BRCore.BRTransaction>.stride), callback: { errorMessage in
            if errorMessage != nil {
                UserDefaults.standard.set(tx.pointee.txHash.description, forKey: "BCashTxHashKey")
            }
            callback(errorMessage)
        })

    }

}

extension BRAPIClient {
    func publishBCashTransaction(txData: Data, callback: @escaping (String?)->Void) {
        //TODO - update to /bch/publish-transaction
        var req = URLRequest(url: url("/bch/publish-transaction-test"))
        req.httpMethod = "POST"
        req.setValue("application/bcashdata", forHTTPHeaderField: "Content-Type")
        req.httpBody = txData
        dataTaskWithRequest(req as URLRequest, authenticated: true, retryCount: 0) { (dat, resp, er) in
            if let statusCode = resp?.statusCode {
                if statusCode >= 200 && statusCode < 300 {
                    callback(nil)
                } else if let error = er{
                    callback(error.description)
                } else {
                    callback("\(statusCode)")
                }
            }
            }.resume()
    }
}

extension Data {
    var masterPubKey: BRMasterPubKey? {
        guard self.count >= (4 + 32 + 33) else { return nil }
        var mpk = BRMasterPubKey()
        mpk.fingerPrint = self.subdata(in: 0..<4).withUnsafeBytes({ $0.pointee })
        mpk.chainCode = self.subdata(in: 4..<(4 + 32)).withUnsafeBytes({ $0.pointee })
        mpk.pubKey = self.subdata(in: (4 + 32)..<(4 + 32 + 33)).withUnsafeBytes({ $0.pointee })
        return mpk
    }
}

extension BRCore.UInt256 : CustomStringConvertible {
    public var description: String {
        return String(format:"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" +
            "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                      self.u8.31, self.u8.30, self.u8.29, self.u8.28, self.u8.27, self.u8.26, self.u8.25, self.u8.24,
                      self.u8.23, self.u8.22, self.u8.21, self.u8.20, self.u8.19, self.u8.18, self.u8.17, self.u8.16,
                      self.u8.15, self.u8.14, self.u8.13, self.u8.12, self.u8.11, self.u8.10, self.u8.9, self.u8.8,
                      self.u8.7, self.u8.6, self.u8.5, self.u8.4, self.u8.3, self.u8.2, self.u8.1, self.u8.0)
    }
}
