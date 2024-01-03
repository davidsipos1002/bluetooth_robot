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

fileprivate enum BluetoothControlMode : Int, CaseIterable {
    case dpad = 0
    case buttons = 1
    case touchpad = 2
    case stick = 3
    
    static func getString(from x: BluetoothControlMode) -> String {
        switch x {
        case .dpad:
            "dpad + left trigger"
        case .buttons:
            "buttons + left trigger"
        case .touchpad:
            "touchpad"
        case .stick:
            "left stick"
        }
    }
}

fileprivate class BluetoothControlThread : Thread {
    private let waiter = DispatchGroup()
    private weak var communication : BluetoothCommunication!
    private var controlMode : BluetoothControlMode! = BluetoothControlMode(rawValue: 0)
    private var modeSet = false
    private var requestSent = false
    private var resetSent = false
    private var moveSent = false
    
    init(communication: BluetoothCommunication) {
        super.init()
        self.communication = communication
    }
    
    override func start() -> Void {
        waiter.enter()
        super.start()
    }
    
    override func main() -> Void {
        testConnection()
    inloop:
        while(true) {
            if let manager = communication.controllerManager {
                if (manager.controllerState.buttonPlayStation) {
                     CFRunLoopStop(CFRunLoopGetMain())
                     break
                }
                
                processSoftwareReset(state: manager.controllerState)
                
                if (resetSent) {
                    CFRunLoopStop(CFRunLoopGetMain())
                    break
                }
                
                processMovement(state: manager.controllerState)
                
                processServo(state: manager.controllerState)
               
                processRequest(state: manager.controllerState)
                
                if (manager.controllerState.buttonPause) {
                    if (modeSet == false) {
                        controlMode = BluetoothControlMode(rawValue: (controlMode!.rawValue + 1) % BluetoothControlMode.allCases.count)
                        print("Current control mode: \(BluetoothControlMode.getString(from: controlMode))")
                        modeSet = true
                    }
                } else {
                    modeSet = false
                }
            } else {
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
                    if (values.count < 3) {
                        print("Invalid move command!")
                        break
                    }
                    let dir = Direction.convertToDirection(fromString: values[1])
                    let speed = Float(values[2])
                    communication.move(direction: dir!, speed: speed!)
                    communication.waitForAcks()
                    print("Command executed")
                case "sr":
                    if (values.count < 2) {
                        print("Invalid servo command")
                    }
                    let amount = Float(values[1])
                    if (amount == nil) {
                        print("Invalid amount")
                        break
                    }
                    communication.servo(amount: amount!)
                    communication.waitForAcks()
                    print("Command executed")
                case "d":
                    communication.distance()
                    communication.waitForAcks()
                    print("Command executed")
                    let dist = communication.getReponseAsFloat()
                    if let d = dist {
                        print("Received: \(d)")
                    } else {
                        print("Received invalid float")
                    }
                default:
                    print("Unknown command!")
                }
            }
        }
        print("Stopping control thread...")
        waiter.leave()
    }
    
    private func testConnection() {
        print("Sending test ACK...")
        var timer = CFRunLoopTimerCreate(kCFAllocatorDefault, Date().timeIntervalSinceReferenceDate + 15, 0, 0, 0, { timer, info in
            print("Connection test failed. Exiting...")
            CFRunLoopStop(CFRunLoopGetMain())
        }, nil)
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer!, CFRunLoopMode.defaultMode)
        communication.write(data: [0xAA])
        communication.waitForResponse()
        CFRunLoopRemoveTimer(CFRunLoopGetMain(), timer!, CFRunLoopMode.defaultMode)
        timer = nil
        print("Connection test succeeded")
    }
    
    private func processSoftwareReset(state: ControllerState) -> Void {
        if (state.leftShoulder && state.rightShoulder && resetSent == false) {
            print("Resetting...")
            communication.write(data: [0x00, 0x00, 0x00, 0xAA])
            resetSent = true
        }
    }
    
    private func processMovement(state: ControllerState) -> Void {
        switch controlMode {
        case .dpad:
            var dir : Direction? = nil
            if (state.dpadUp) {
                dir = .forward
            } else if (state.dpadDown) {
                dir = .backward
            } else if (state.dpadLeft) {
                dir = .left
            } else if (state.dpadRight) {
                dir = .right
            }
            if (dir != nil && state.leftTrigger > 0) {
                communication.move(direction: dir!, speed: state.leftTrigger)
                communication.waitForAcks()
                moveSent = true
            } else if (moveSent == true) {
                communication.move(direction: .forward, speed: 0)
                communication.waitForAcks()
                moveSent = false
            }
        case .buttons:
            var dir : Direction? = nil
            if (state.buttonTriangle) {
                dir = .forward
            } else if (state.buttonX) {
                dir = .backward
            } else if (state.buttonSquare) {
                dir = .left
            } else if (state.buttonCircle) {
                dir = .right
            }
            if (dir != nil) {
                communication.move(direction: dir!, speed: state.leftTrigger)
                communication.waitForAcks()
                moveSent = true
            } else if (moveSent == true) {
                communication.move(direction: .forward, speed: 0)
                communication.waitForAcks()
                moveSent = false
            }
        case .touchpad:
            var dir : Direction? = nil
            var displacement : Float = 0
            if (abs(state.touchPadPrimaryFinger.x) > displacement) {
                displacement = abs(state.touchPadPrimaryFinger.x)
                dir = state.touchPadPrimaryFinger.x < 0 ? .left : .right
            }
            if (abs(state.touchPadPrimaryFinger.y) > displacement) {
                displacement = abs(state.touchPadPrimaryFinger.y)
                dir = state.touchPadPrimaryFinger.y > 0 ? .forward : .backward
            }
            if (dir != nil) {
                communication.move(direction: dir!, speed: displacement)
                communication.waitForAcks()
                moveSent = true
            } else if (moveSent == true) {
                communication.move(direction: .forward, speed: 0)
                communication.waitForAcks()
                moveSent = false
            }
        case .stick:
            var dir : Direction? = nil
            var displacement : Float = 0
            if (abs(state.leftThumbstick.x) > displacement) {
                displacement = abs(state.leftThumbstick.x)
                dir = state.leftThumbstick.x < 0 ? .left : .right
            }
            if (abs(state.leftThumbstick.y) > displacement) {
                displacement = abs(state.leftThumbstick.y)
                dir = state.leftThumbstick.y > 0 ? .forward : .backward
            }
            if (dir != nil) {
                communication.move(direction: dir!, speed: displacement)
                communication.waitForAcks()
                moveSent = true
            } else if (moveSent == true) {
                communication.move(direction: .forward, speed: 0)
                communication.waitForAcks()
                moveSent = false
            }
        case .none:
            break
        }
    }
    
    private func processServo(state: ControllerState) -> Void {
        let amount = state.rightThumbstick.x
        if (abs(amount) > 0) {
            communication.servo(amount: amount)
            communication.waitForAcks()
        }
    }
    
    private func processRequest(state: ControllerState) -> Void {
        if (state.buttonShare) {
            if (requestSent == false) {
                communication.distance()
                communication.waitForAcks()
                let distance = communication.getReponseAsFloat()
                if let d = distance {
                    print("Distance: \(d)")
                } else {
                    print("Received invalid value")
                }
                requestSent = true
            }
        } else {
            requestSent = false
        }
    }
    
    func join() -> Bool {
        if (waiter.wait(timeout: DispatchTime.now() + DispatchTimeInterval.seconds(10)) == .timedOut) {
            return false
        }
        return true
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
    fileprivate var minSpeed : UInt8
    fileprivate let maxSpeed : UInt8
    fileprivate let minServoDisplacement : Int16
    fileprivate let maxServoDisplacement : Int16

  
    init(channel: IOBluetoothRFCOMMChannel, manager: ControllerManager?, minSpeed: UInt8, maxSpeed: UInt8, minServoDisplacement: Int16, maxServoDisplacement: Int16) {
        self.channel = channel
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
        self.minServoDisplacement = minServoDisplacement
        self.maxServoDisplacement = maxServoDisplacement
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
    
    private func format(request: UInt8, type: UInt8, dir: UInt8,value: UInt8) -> [UInt8] {
        var controlByte : UInt8 = 0
        controlByte |= request << 7
        controlByte |= type << 5
        controlByte |= dir << 4
        return [controlByte, value]
    }
    
    fileprivate func move(direction: Direction, speed: Float) -> Void {
        var command : [UInt8] = []
        var finalSpeed : UInt8 = 0
        if (speed > 0) {
            finalSpeed = UInt8(Float(minSpeed) * (1 - speed) + Float(maxSpeed) * speed)
        }
        switch direction {
        case .forward:
            command = format(request: 0, type: 0, dir: 0, value: finalSpeed)
        case .backward:
            command = format(request: 0, type: 0, dir: 1, value: finalSpeed)
        case .left:
            command = format(request: 0, type: 1, dir: 0, value: finalSpeed)
        case .right:
            command = format(request: 0, type: 1, dir: 1, value: finalSpeed)
        }
        command.append(0xAA)
        write(data: command)
    }
    
    fileprivate func servo(amount: Float) -> Void {
        var command : [UInt8] = []
        var finalAmount : UInt8 = 0
        let posAmount = abs(amount)
        if (posAmount > 0) {
            finalAmount = UInt8(Float(minServoDisplacement) * (1 - posAmount) + Float(maxServoDisplacement) * posAmount)
        }
        if (amount >= 0) {
            command = format(request: 0, type: 2, dir: 1, value: finalAmount)
        } else {
            command = format(request: 0, type: 2, dir: 0, value: finalAmount)
        }
        command.append(0xAA)
        write(data: command)
    }
    
    fileprivate func distance() -> Void {
        var request : [UInt8] = []
        request = format(request: 1, type: 0, dir: 0, value: 0)
        request.removeLast()
        request.append(0xAA)
        write(data: request)
    }

    fileprivate func waitForAcks() -> Void {
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
        print("ACK_DONE")
    }
    
    fileprivate func getReponseAsFloat() -> Float? {
        guard (contextInfo.response.count >= 4) else {
            return nil
        }
        let bitPattern = contextInfo.response.withUnsafeBytes { ptr in
            var ret : UInt32 = 0
            for i in 0..<4 {
                ret |= UInt32(ptr.load(fromByteOffset: i, as: UInt8.self)) << (8 * i)
            }
            return ret
        }
        return Float(bitPattern: bitPattern)
    }
    
    func end() -> Void {
        if (thread.join() == false) {
            print("Could not join control thread. Cancelling...")
            thread.cancel()
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), writeSource, CFRunLoopMode.defaultMode)
        writeSource = nil
        writeContext = nil
        channel.close()
        channel.getDevice().closeConnection()
    }
}
