//
//  BluetoothComm.swift
//  DMP_Project
//
//  Created by David-Oliver Sipos on 01.01.2024.
//

import Foundation
import IOBluetooth

fileprivate enum Direction {
    case forward
    case backward
    case left
    case right
   
    static func convertToDirection(fromString str: String) -> Direction? {
        switch str {
        case "f":
            return .forward
        case "b":
            return .backward
        case "l":
            return .left
        case "r":
            return .right
        default:
            return nil
        }
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
    inloop: 
        while(true) {
            let values = readLine()!.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            if (values.count == 0) {
                continue
            }
            switch values[0] {
            case "s":
                CFRunLoopStop(CFRunLoopGetMain())
                break inloop
            case "rb":
                communication.read()
            case "rs":
                communication.read(true)
            case "Wb":
                communication.waitForResponse()
            case "Ws":
                communication.waitForResponse(true)
            case "wb":
                let hexString = values[1].lowercased().replacing("0x", with: "")
                communication.write(data: [UInt8(hexString, radix: 16)!])
            case "ws":
                communication.write(data: Array(values[1].utf8))
            case "m":
                if (values.count < 4) {
                    print("Invalid move command!")
                    break
                }
                let dir = Direction.convertToDirection(fromString: values[1])
                let duration = UInt8(values[2])
                let speed = UInt8(values[3])
                communication.move(direction: dir!, duration: duration!, speed: speed!)
            default:
                print("Unknown command!")
            }
        }
        print("Stopping control thread...")
        waiter.leave()
    }
    
    func join() -> Void {
        waiter.wait()
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
    
    fileprivate func printMessagesUnsafe(_ printAsString: Bool) -> Void {
        print("Received messages:")
        for msg in contextInfo.receivedData {
            if (printAsString) {
                print("    * \(String(bytes: msg, encoding: String.Encoding.ascii)!)")
            } else {
                print("    * \(msg)")
            }
        }
        contextInfo.receivedData.removeAll()
    }
    
    fileprivate func read(_ printAsString: Bool = false) -> Void {
        contextInfo.mutex.lock()
        printMessagesUnsafe(printAsString)
        contextInfo.receivedData.removeAll()
        contextInfo.mutex.unlock()
    }
    
    fileprivate func waitForResponse(_ printAsString: Bool = false) -> Void {
        contextInfo.mutex.lock()
        while(contextInfo.receivedData.count == 0) {
            contextInfo.mutex.wait()
        }
        printMessagesUnsafe(printAsString)
        contextInfo.mutex.unlock()
    }
    
    private func format(request: UInt8, type: UInt8, dir: UInt8, duration: UInt8, value: UInt8) -> [UInt8] {
        var controlByte : UInt8 = 0
        controlByte |= request << 7
        controlByte |= type << 5
        controlByte |= dir << 4
        controlByte |= duration & 0x0F
        return [controlByte, value]
    }
    
    fileprivate func move(direction: Direction, duration: UInt8, speed: UInt8) -> Void {
        var command : [UInt8] = []
        switch direction {
        case .forward:
            command = format(request: 0, type: 0, dir: 0, duration: duration, value: speed)
        case .backward:
            command = format(request: 0, type: 0, dir: 1, duration: duration, value: speed)
        case .left:
            command = format(request: 0, type: 1, dir: 0, duration: duration, value: speed)
        case .right:
            command = format(request: 0, type: 1, dir: 1, duration: duration, value: speed)
        }
        write(data: command)
    }
    
    fileprivate func waitForAck(type: Bool) -> Void {
        var done = false
        while (!done) {
            contextInfo.mutex.lock()
            while(contextInfo.receivedData.count == 0) {
                contextInfo.mutex.wait()
            }
            let expectedAck : UInt8 = type ? 0x55 : 0xAA
            for msg in contextInfo.receivedData {
                if msg[0] == expectedAck {
                    done = true
                    break
                }
            }
            contextInfo.receivedData.removeAll()
            contextInfo.mutex.unlock()
        }
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
