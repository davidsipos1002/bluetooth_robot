//
//  DeviceDiscovery.swift
//  DMP_Project
//
//  Created by David-Oliver Sipos on 01.01.2024.
//

import Foundation
import IOBluetooth

fileprivate class DeviceDiscoveryDelegate: NSObject, IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        print("Device found with address: \(device.addressString!).")
    }
}

final class DeviceDiscovery
{
    let deviceName: String;
    let searchTime: Int;
    let baudRate: UInt32;
    let byteSize: UInt8;
    let parity: BluetoothRFCOMMParityType;
    let stopBits: UInt8;
    
    init(deviceName: String, searchTime: Int, baudRate: UInt32, byteSize: UInt8, parity: BluetoothRFCOMMParityType, stopBits: UInt8) {
        self.deviceName = deviceName
        self.searchTime = searchTime
        self.baudRate = baudRate
        self.byteSize = byteSize
        self.parity = parity
        self.stopBits = stopBits
    }
    
    func startDiscovery() -> IOBluetoothRFCOMMChannel! {
        print("Starting device discovery. Timeout is \(searchTime)s.")
        let inquiryDelegate = DeviceDiscoveryDelegate()
        let deviceInquiry: IOBluetoothDeviceInquiry! = IOBluetoothDeviceInquiry(delegate: inquiryDelegate)
        var timer = CFRunLoopTimerCreate(kCFAllocatorDefault, Date().timeIntervalSinceReferenceDate + Double(searchTime), 0, 0, 0, { timer, info in
            CFRunLoopStop(CFRunLoopGetCurrent())
        }, nil)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.defaultMode)
        deviceInquiry.start()
        CFRunLoopRun()
        deviceInquiry.stop()
        CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.defaultMode)
        timer = nil
        print("Discovery finished.")
        print("Found devices:")
        let foundDevices = deviceInquiry.foundDevices()
        var deviceToConnect : IOBluetoothDevice?
        for element in foundDevices! {
            let device = element as! IOBluetoothDevice
            if (device.remoteNameRequest(nil) != kIOReturnSuccess) {
                print("Could not perform remote name request!")
                continue
            }
            print("")
            print("Device name: \(device.name!)")
            if (device.name! == deviceName) {
                if (device.performSDPQuery(nil) != kIOReturnSuccess) {
                    print("Could not perform SDP query. Ignoring device.")
                    continue
                } else {
                    while(device.getLastServicesUpdate().compare(Date()) != .orderedAscending) {
                    }
                    print("   Supported services:")
                    for service in device.services! {
                        let serviceRecord = service as! IOBluetoothSDPServiceRecord
                        print("      \(serviceRecord.getServiceName() ?? "Unnamed Service")")
                        var rfcommChannelID : BluetoothRFCOMMChannelID = 0
                        if (serviceRecord.getRFCOMMChannelID(&rfcommChannelID) == kIOReturnSuccess) {
                            print("           Found RFCOMM channel with ID: \(rfcommChannelID)")
                        }
                    }
                    deviceToConnect = device
                }
            }
        }
        print("")
        var rfcommChannel : IOBluetoothRFCOMMChannel?
        if (deviceToConnect != nil) {
            print("Device \(deviceName) found. Enter RFCOMM channel ID to open connection: ", terminator: "")
            let id : BluetoothRFCOMMChannelID! = UInt8(readLine()!)
            if (deviceToConnect!.openConnection() == kIOReturnSuccess) {
                if (deviceToConnect!.openRFCOMMChannelSync(&rfcommChannel, withChannelID: id, delegate: NSObject()) == kIOReturnSuccess) {
                    if (rfcommChannel!.setSerialParameters(baudRate, dataBits: byteSize, parity: parity, stopBits: stopBits) == kIOReturnSuccess) {
                        print("Connection established.")
                    } else {
                        print("Failed to set channel parameters!")
                        rfcommChannel!.close()
                        rfcommChannel = nil
                    }
                } else {
                    print("Failed to open RFCOMM channel!")
                    if (rfcommChannel != nil) {
                        rfcommChannel!.close()
                    }
                    rfcommChannel = nil
                }
            } else {
                print("Could not open connection!")
            }
        }
        return rfcommChannel
    }
}
