//
//  ControllerManager.swift
//  DMP_Project
//
//  Created by David-Oliver Sipos on 02.01.2024.
//

import Foundation
import GameController

fileprivate class ControllerConnectionObserver {
    private weak var manager : ControllerManager! = nil
    
    init(manager: ControllerManager!) {
        self.manager = manager
    }
    
    @objc func controllerConnected(notification: NSNotification) -> Void {
        manager.controller = GCController.current
        manager.extendedController = GCController.current!.extendedGamepad
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
    
    @objc func controllerDisconnected(notification: NSNotification) -> Void {
        print("Controller disconnected. Stopping program...")
        exit(1)
    }
}

struct ControllerPosition {
    var x : Float = 0
    var y : Float = 0
}

struct ControllerState {
    var buttonX : Bool = false
    var buttonTriangle : Bool = false
    var buttonCircle : Bool = false
    var buttonSquare : Bool = false
    var buttonPlayStation : Bool = false
    var buttonShare : Bool = false
    var buttonPause : Bool = false
    var dpadLeft : Bool = false
    var dpadRight : Bool = false
    var dpadUp : Bool = false
    var dpadDown : Bool = false
    var leftShoulder : Bool = false
    var leftTrigger : Float = 0
    var rightShoulder : Bool = false
    var rightTrigger : Float = 0
    var buttonLeftThumbstick : Bool = false
    var leftThumbstick : ControllerPosition = ControllerPosition()
    var buttonRightThumbstick : Bool = false
    var rightThumbstick : ControllerPosition = ControllerPosition()
    var buttonTouchPad : Bool = false
    var touchPadPrimaryFinger : ControllerPosition = ControllerPosition()
    var touchPadSecondaryFinger : ControllerPosition =  ControllerPosition()
}

class ControllerManager {
    private var observer : ControllerConnectionObserver! = nil
    fileprivate var controller : GCController! = nil
    fileprivate var extendedController : GCExtendedGamepad! = nil
    private(set) var controllerState = ControllerState()
    private var timer : CFRunLoopTimer! = nil
    
    init() {
        self.observer = ControllerConnectionObserver(manager: self)
        GCController.shouldMonitorBackgroundEvents = true
    }
    
    func batteryStateToString(_ state: GCDeviceBattery.State) -> String {
        switch state {
        case .unknown:
            "Unknown"
        case .charging:
            "Charging"
        case .discharging:
            "Discharing"
        case .full:
            "Fully charged"
        @unknown default:
            fatalError("unknown battery state!")
        }
    }
    
    private func setTimeoutTimer(_ timeout: Double) -> Void {
        timer = CFRunLoopTimerCreate(kCFAllocatorDefault, Date().timeIntervalSinceReferenceDate + timeout, 0, 0, 0, { timer, info in
            CFRunLoopStop(CFRunLoopGetCurrent())
        }, nil)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.defaultMode)
    }
    
    func waitForController(_ timeout: Double) -> Bool {
        NotificationCenter.default.addObserver(observer!, selector: #selector(ControllerConnectionObserver.controllerConnected), name: NSNotification.Name.GCControllerDidConnect, object: nil)
        setTimeoutTimer(timeout)
        CFRunLoopRun()
        CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.defaultMode)
        NotificationCenter.default.removeObserver(observer!, name: NSNotification.Name.GCControllerDidConnect, object: nil)
        timer = nil
        if (GCController.controllers().count == 0) {
            print("Controller search timeout. Defaulting to CLI mode.")
        } else {
            NotificationCenter.default.addObserver(observer!, selector: #selector(ControllerConnectionObserver.controllerDisconnected), name: NSNotification.Name.GCControllerDidDisconnect, object: nil)
            extendedController.valueChangedHandler = self.handleChange
            controller.playerIndex = .index1
            setLightColor(red: 1, green: 0, blue: 0)
            Thread.sleep(forTimeInterval: 1)
            if (extendedController is GCXboxGamepad) {
                print("Controller not supported. Defaulting to CLI mode.")
                return false
            }
            print("Controller connected. Battery level: \(controller.battery!.batteryLevel * 100.0). Battery state: \(batteryStateToString(controller.battery!.batteryState))")
            return true
        }
        return false
    }
    
    func setLightColor(red: Float, green: Float, blue: Float) -> Void {
        controller.light!.color = GCColor(red: red, green: green, blue: blue)
    }
    
    private func handleChange(gamepad: GCExtendedGamepad, element: GCControllerElement) -> Void {
        controllerState.buttonX = gamepad.buttonA.isPressed
        controllerState.buttonTriangle = gamepad.buttonY.isPressed
        controllerState.buttonCircle = gamepad.buttonB.isPressed
        controllerState.buttonSquare = gamepad.buttonX.isPressed
        controllerState.buttonPlayStation = gamepad.buttonHome!.isPressed
        controllerState.buttonPause = gamepad.buttonMenu.isPressed
        controllerState.buttonShare = gamepad.buttonOptions!.isPressed
        controllerState.dpadLeft = gamepad.dpad.left.isPressed
        controllerState.dpadRight = gamepad.dpad.right.isPressed
        controllerState.dpadUp = gamepad.dpad.up.isPressed
        controllerState.dpadDown = gamepad.dpad.down.isPressed
        controllerState.leftShoulder = gamepad.leftShoulder.isPressed
        controllerState.leftTrigger = gamepad.leftTrigger.value
        controllerState.rightShoulder = gamepad.rightShoulder.isPressed
        controllerState.rightTrigger = gamepad.rightTrigger.value
        controllerState.buttonLeftThumbstick = gamepad.leftThumbstickButton!.isPressed
        controllerState.leftThumbstick.x = gamepad.leftThumbstick.xAxis.value
        controllerState.leftThumbstick.y = gamepad.leftThumbstick.yAxis.value
        controllerState.buttonRightThumbstick = gamepad.rightThumbstickButton!.isPressed
        controllerState.rightThumbstick.x = gamepad.rightThumbstick.xAxis.value
        controllerState.rightThumbstick.y = gamepad.rightThumbstick.yAxis.value
        if (gamepad is GCDualShockGamepad) {
            let dualShock = gamepad as! GCDualShockGamepad
            controllerState.buttonTouchPad = dualShock.touchpadButton.isPressed
            controllerState.touchPadPrimaryFinger.x = dualShock.touchpadPrimary.xAxis.value
            controllerState.touchPadPrimaryFinger.y = dualShock.touchpadPrimary.yAxis.value
            controllerState.touchPadSecondaryFinger.x = dualShock.touchpadSecondary.xAxis.value
            controllerState.touchPadSecondaryFinger.y = dualShock.touchpadSecondary.yAxis.value
        } else {
            let dualSense = gamepad as! GCDualSenseGamepad
            controllerState.buttonTouchPad = dualSense.touchpadButton.isPressed
            controllerState.touchPadPrimaryFinger.x = dualSense.touchpadPrimary.xAxis.value
            controllerState.touchPadPrimaryFinger.y = dualSense.touchpadPrimary.yAxis.value
            controllerState.touchPadSecondaryFinger.x = dualSense.touchpadSecondary.xAxis.value
            controllerState.touchPadSecondaryFinger.y = dualSense.touchpadSecondary.yAxis.value
        }
    }
}
