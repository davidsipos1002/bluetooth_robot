//
//  BluetoothComm.swift
//  DMP_Project
//
//  Created by David-Oliver Sipos on 01.01.2024.
//

import Foundation
import IOBluetooth

fileprivate class BluetoothControlThread : Thread {
    let waiter = DispatchGroup()
    
    override func start() -> Void {
        waiter.enter()
        super.start()
    }
    
    override func main() -> Void {
        var line : String!
        while(true) {
            line = readLine()
            if (line == "stop") {
                CFRunLoopStop(CFRunLoopGetMain())
                break
            }
        }
        print("Stopping control thread")
        waiter.leave()
    }
    
    func join() -> Void {
        waiter.wait()
    }
}

class BluetoothCommunication {
    let channel : IOBluetoothRFCOMMChannel
    fileprivate let thread = BluetoothControlThread()
    
    init(channel: IOBluetoothRFCOMMChannel) {
        self.channel = channel
    }
    
    func start() -> Void {
        thread.start()
    }
    
    func end() -> Void {
        thread.join()
    }
}
