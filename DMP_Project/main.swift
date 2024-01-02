//
//  main.swift
//  DMP_Project
//
//  Created by David-Oliver Sipos on 01.01.2024.
//

import Foundation
import IOBluetooth

func main() -> Void
{
    print("Controller search timeout: ", terminator: "")
    let timeout = Int(readLine()!)
    print("Waiting for controller. Timeout is \(timeout!)s.")
    let controllerManager = ControllerManager()
    let controllerFound = controllerManager.waitForController(timeout!)
    print("Device name: ", terminator: "")
    let name = readLine()
    print("Search time: ", terminator: "")
    let btTimeout = Int(readLine()!)
    print("Baud rate: ", terminator: "")
    let baud = UInt32(readLine()!)
    let discovery = DeviceDiscovery(deviceName: name!, searchTime: btTimeout!, baudRate: baud!, byteSize: 8, parity: kBluetoothRFCOMMParityTypeNoParity, stopBits: 1)
    let rfcommChannel = discovery.startDiscovery()
    if (rfcommChannel != nil) {
        let communication = BluetoothCommunication(channel: rfcommChannel!, manager: controllerFound ? controllerManager : nil)
        communication.start()
        controllerManager.setLightColor(red: 0.36 , green: 0.6 , blue: 0)
        CFRunLoopRun()
        communication.end()
    }
    controllerManager.setLightColor(red: 0, green: 0, blue: 0)
    print("Ending program...")
}

main()
