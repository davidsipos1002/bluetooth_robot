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
    let discovery = DeviceDiscovery(deviceName: "Test", searchTime: 10, baudRate: 9600, byteSize: 8, parity: kBluetoothRFCOMMParityTypeNoParity, stopBits: 1)
    let rfcommChannel = discovery.startDiscovery()
    if (rfcommChannel != nil) {
        let communication = BluetoothCommunication(channel: rfcommChannel!)
        communication.start()
        CFRunLoopRun()
        communication.end()
    }
}

main()
