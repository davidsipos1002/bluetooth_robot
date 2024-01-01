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
    print("Device name: ", terminator: "")
    let name = readLine()
    print("Search time: ", terminator: "")
    let timeout = Int(readLine()!)
    print("Baud rate: ", terminator: "")
    let baud = UInt32(readLine()!)
    let discovery = DeviceDiscovery(deviceName: name!, searchTime: timeout!, baudRate: baud!, byteSize: 8, parity: kBluetoothRFCOMMParityTypeNoParity, stopBits: 1)
    let rfcommChannel = discovery.startDiscovery()
    if (rfcommChannel != nil) {
        let communication = BluetoothCommunication(channel: rfcommChannel!)
        communication.start()
        CFRunLoopRun()
        communication.end()
   }
}

main()
