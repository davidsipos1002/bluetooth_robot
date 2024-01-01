//
//  BluetoothComm.swift
//  DMP_Project
//
//  Created by David-Oliver Sipos on 01.01.2024.
//

import Foundation
import IOBluetooth

fileprivate class BluetoothControlThread : Thread {
    private let waiter = DispatchGroup()
    private weak var communication : BluetoothCommunication!
    
    init(communication: BluetoothCommunication) {
        super.init()
        self.communication = communication
    }
    
    override func start() -> Void {
        waiter.enter()
        super.start()
    }
    
    override func main() -> Void {
        var line : String!
        while(true) {
            line = readLine()
            if (line == "s") {
                CFRunLoopStop(CFRunLoopGetMain())
                break
            } else if (line.starts(with: "w")) {
                line.removeFirst(2)
                communication.write(data: Array(line!.utf8))
            } else if (line.starts(with: "r")) {
                communication.read()
            } else if (line.starts(with: "W")) {
                communication.waitForResponse()
            }
        }
        print("Stopping control thread...")
        waiter.leave()
    }
    
    func join() -> Void {
        waiter.wait()
    }
}

fileprivate class BluetoothInfo {
    let mutex = NSCondition()
    let channel : IOBluetoothRFCOMMChannel
    var message : [UInt8] = []
    var receivedData : [[UInt8]] = []
    
    init(channel: IOBluetoothRFCOMMChannel) {
        self.channel = channel
    }
}

fileprivate class BluetoothRFCOMMDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    
    private weak var contextInfo : BluetoothInfo!
    
    init(contextInfo: BluetoothInfo!) {
        self.contextInfo = contextInfo
    }
    
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        contextInfo.mutex.lock()
        let start : UnsafeMutablePointer<UInt8> = dataPointer.bindMemory(to: UInt8.self, capacity: dataLength)
        let charArray = Array<UInt8>(unsafeUninitializedCapacity: dataLength) { buffer, initializedCount in
            initializedCount = dataLength
            _ = buffer.moveUpdate(fromContentsOf: UnsafeMutableBufferPointer(start: start, count: dataLength))
        }
        contextInfo.receivedData.append(charArray)
        contextInfo.mutex.signal()
        contextInfo.mutex.unlock()
    }
}

class BluetoothCommunication {
    private let channel : IOBluetoothRFCOMMChannel
    private var thread : BluetoothControlThread! = nil
    private var contextInfo : BluetoothInfo! = nil
    private var channelDelegate : BluetoothRFCOMMDelegate! = nil
    private var writeSource : CFRunLoopSource! = nil
    private var writeContext : CFRunLoopSourceContext! = nil
  
    init(channel: IOBluetoothRFCOMMChannel) {
        self.channel = channel
        self.thread = BluetoothControlThread(communication: self)
        self.contextInfo = BluetoothInfo(channel: channel)
        self.channelDelegate = BluetoothRFCOMMDelegate(contextInfo: contextInfo)
    }
    
    private func getUnsafeMutablePointer<T> (to value: inout T) -> UnsafeMutableRawPointer! {
        withUnsafeMutablePointer(to: &value) {UnsafeMutableRawPointer($0)}
    }
    
    func start() -> Void {
        channel.setDelegate(channelDelegate)
        writeContext = CFRunLoopSourceContext(version: 0, info: getUnsafeMutablePointer(to: &contextInfo), retain: nil, release: nil, copyDescription: nil, equal: nil, hash: nil, schedule: nil, cancel: nil, perform: { info in
            let bluetoothInfo = (info!.bindMemory(to: BluetoothInfo.self, capacity: 1)).pointee
            bluetoothInfo.mutex.lock()
            let ptr = bluetoothInfo.message.withUnsafeMutableBytes {$0.baseAddress}
            bluetoothInfo.channel.writeAsync(ptr, length: UInt16(bluetoothInfo.message.count), refcon: nil)
            bluetoothInfo.mutex.unlock()
        })
        writeSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &writeContext)
        CFRunLoopAddSource(CFRunLoopGetMain(), writeSource, CFRunLoopMode.defaultMode)
        print("Spawning control thread...")
        thread.start()
    }
    

    fileprivate func write(data: [UInt8]) -> Void {
        contextInfo.mutex.lock()
        contextInfo.message = data
        contextInfo.mutex.unlock()
        CFRunLoopSourceSignal(writeSource)
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
    
    fileprivate func printMessagesUnsafe() -> Void {
        print("Received messages:")
        for msg in contextInfo.receivedData {
            print("    * \(msg)")
        }
        contextInfo.receivedData.removeAll()
    }
    
    fileprivate func read() -> Void {
        contextInfo.mutex.lock()
        printMessagesUnsafe()
        contextInfo.receivedData.removeAll()
        contextInfo.mutex.unlock()
    }
    
    fileprivate func waitForResponse() -> Void {
        contextInfo.mutex.lock()
        while(contextInfo.receivedData.count == 0) {
            contextInfo.mutex.wait()
        }
        printMessagesUnsafe()
        contextInfo.mutex.unlock()
    }
    
    func end() -> Void {
        thread.join()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), writeSource, CFRunLoopMode.defaultMode)
        writeSource = nil
        writeContext = nil
        channel.close()
        channel.getDevice().closeConnection()
    }
}
