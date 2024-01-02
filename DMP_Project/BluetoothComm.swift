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
    var response : [UInt8] = []
    
    init(channel: IOBluetoothRFCOMMChannel) {
        self.channel = channel
    }
}

fileprivate class BluetoothRFCOMMDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    
    private weak var contextInfo : BluetoothInfo!
    
    init(contextInfo: BluetoothInfo!) {
        self.contextInfo = contextInfo
    }
    
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        print("Lost connection! Exiting...")
        exit(EXIT_FAILURE)
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
            if (communication.controllerManager == nil) {
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
                    communication.waitForAcks()
                    print("Command executed")
                default:
                    print("Unknown command!")
                }
            } else {
               if (communication.controllerManager!.controllerState.buttonPlayStation) {
                    CFRunLoopStop(CFRunLoopGetMain())
                    break
               }
            }
        }
        print("Stopping control thread...")
        waiter.leave()
    }
    
    private func processMovement() -> Void {
        
    }
    
    private func processServo() -> Void {
        
    }
    
    private func processRequest() -> Void {
        
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
    fileprivate var controllerManager : ControllerManager! = nil
  
    init(channel: IOBluetoothRFCOMMChannel, manager: ControllerManager?) {
        self.channel = channel
        self.thread = BluetoothControlThread(communication: self)
        self.contextInfo = BluetoothInfo(channel: channel)
        self.channelDelegate = BluetoothRFCOMMDelegate(contextInfo: contextInfo)
        self.controllerManager = manager
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
        command.append(0xAA)
        write(data: command)
    }
    
    fileprivate func servo(amount: Int16) -> Void {
        var command : [UInt8] = []
        if (amount >= 0) {
            command = format(request: 0, type: 2, dir: 0, duration: 0xF, value: UInt8(amount & 0xFF))
        } else {
            let posAmount = -amount
            command = format(request: 0, type: 2, dir: 1, duration: 0xF, value: UInt8(posAmount & 0xFF))
        }
        command.append(0xAA)
        write(data: command)
    }
    
    fileprivate func distance() -> Void {
        var request : [UInt8] = []
        request = format(request: 1, type: 0, dir: 0, duration: 0, value: 0)
        request.removeLast()
        request.append(0xAA)
        write(data: request)
    }
    
    fileprivate func waitForAcks() {
        var done = false
        while (!done) {
            defer {
                contextInfo.mutex.unlock()
                if (!done) {
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            contextInfo.mutex.lock()
            while(contextInfo.receivedData.count == 0) {
                contextInfo.mutex.wait()
            }
            var recvAck = false
            var doneAck = false
            contextInfo.response.removeAll()
            for msg in contextInfo.receivedData {
                for b in msg {
                    if (b == 0x55) {
                        recvAck = true
                    } else if (b == 0xAA) {
                        doneAck = true
                    } else {
                        contextInfo.response.append(b)
                    }
                }
            }
            done = recvAck && doneAck
            if (done) {
                contextInfo.receivedData.removeAll()
            }
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
