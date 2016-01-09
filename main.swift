//
//  main.swift
//  USBPrivateDataSample
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/1/5.
//
//
/*
    File:			USBPrivateDataSample.c

    Description:	This sample demonstrates how to use IOKitLib and IOUSBLib to set up asynchronous
					callbacks when a USB device is attached to or removed from the system.
					It also shows how to associate arbitrary data with each device instance.

    Copyright:		© Copyright 2001-2006 Apple Computer, Inc. All rights reserved.

    Disclaimer:		IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
					("Apple") in consideration of your agreement to the following terms, and your
					use, installation, modification or redistribution of this Apple software
					constitutes acceptance of these terms.  If you do not agree with these terms,
					please do not use, install, modify or redistribute this Apple software.

					In consideration of your agreement to abide by the following terms, and subject
					to these terms, Apple grants you a personal, non-exclusive license, under Apple’s
					copyrights in this original Apple software (the "Apple Software"), to use,
					reproduce, modify and redistribute the Apple Software, with or without
					modifications, in source and/or binary forms; provided that if you redistribute
					the Apple Software in its entirety and without modifications, you must retain
					this notice and the following text and disclaimers in all such redistributions of
					the Apple Software.  Neither the name, trademarks, service marks or logos of
					Apple Computer, Inc. may be used to endorse or promote products derived from the
					Apple Software without specific prior written permission from Apple.  Except as
					expressly stated in this notice, no other rights or licenses, express or implied,
					are granted by Apple herein, including but not limited to any patent rights that
					may be infringed by your derivative works or by other works in which the Apple
					Software may be incorporated.

					The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
					WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
					WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
					PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
					COMBINATION WITH YOUR PRODUCTS.

					IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
					CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
					GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
					ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
					OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
					(INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
					ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	Change History (most recent first):

            1.2	 	10/04/2006			Updated to produce a universal binary. Now requires Xcode 2.2.1 or
										later to build. Modernized and incorporated bug fixes.

			1.1		04/24/2002			Added comments, release of interface object, use of USB location ID

			1.0	 	10/30/2001			New sample.

*/

import Foundation
import CoreFoundation

import IOKit
import IOKit.usb.IOUSBLib

// Change these two constants to match your device's idVendor and idProduct.
// Or, just pass your idVendor and idProduct as command line arguments when running this sample.
let kMyVendorID	=		1351
let kMyProductID =		8193

struct MyPrivateData {
    var notification: io_object_t = 0
    var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>> = nil
    var deviceName: String?
    var locationID: UInt32 = 0
}

extension UnsafeMutablePointer: OutputStreamType {
    public func write(string: String) {
        if Memory.self is FILE.Type {
            let filePtr = UnsafeMutablePointer<FILE>(self)
            fputs(string, filePtr)
        }
    }
}

//from mach/error.h
func err_system(x: UInt32)->UInt32 {return (((x)&0x3f)<<26)}
func err_sub(x: UInt32)->UInt32 {return (((x)&0xfff)<<14)}

//from IOReturn.h
let sys_iokit =                       err_system(0x38)
let sub_iokit_common =                err_sub(0)

//from IOMessage.h
func iokit_common_msg(message: UInt32)->UInt32 {return (sys_iokit|sub_iokit_common|message)}

let kIOMessageServiceIsTerminated      = iokit_common_msg(0x010)
let kIOMessageServiceIsSuspended       = iokit_common_msg(0x020)
let kIOMessageServiceIsResumed         = iokit_common_msg(0x030)

let kIOMessageServiceIsRequestingClose = iokit_common_msg(0x100)
let kIOMessageServiceIsAttemptingOpen  = iokit_common_msg(0x101)
let kIOMessageServiceWasClosed         = iokit_common_msg(0x110)

let kIOMessageServiceBusyStateChange   = iokit_common_msg(0x120)

let kIOMessageConsoleSecurityChange    = iokit_common_msg(0x128)

let kIOMessageServicePropertyChange    = iokit_common_msg(0x130)

let kIOMessageCopyClientID             = iokit_common_msg(0x330)

let kIOMessageSystemCapabilityChange   = iokit_common_msg(0x340)
let kIOMessageDeviceSignaledWakeup     = iokit_common_msg(0x350)

//from IOUSBLib.h
let kIOUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
let kIOUSBDeviceInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
    0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

//from IOCFPlugin.h
let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
    0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)


private var gNotifyPort: IONotificationPortRef = nil
private var gAddedIter: io_iterator_t = 0
private var gRunLoop: CFRunLoop?

//================================================================================================
//
//	DeviceNotification
//
//	This routine will get called whenever any kIOGeneralInterest notification happens.  We are
//	interested in the kIOMessageServiceIsTerminated message so that's what we look for.  Other
//	messages are defined in IOMessage.h.
//
//================================================================================================
func DeviceNotification(refCon: UnsafeMutablePointer<Void>, service: io_service_t, messageType: natural_t, messageArgument: UnsafeMutablePointer<Void>) {
    let privateDataRef = UnsafeMutablePointer<MyPrivateData>(refCon)
    
    if messageType == kIOMessageServiceIsTerminated {
        print("Device removed.", toStream: &stderr)
        
        // Dump our private data to stderr just to see what it looks like.
        print("privateDataRef->deviceName: ", toStream: &stderr)
        CFShow(privateDataRef.memory.deviceName)
        print("privateDataRef->locationID: 0x\(privateDataRef.memory.locationID).\n", toStream: &stderr)
        
        // Free the data we're no longer using now that the device is going away
        
        if privateDataRef.memory.deviceInterface != nil {
            _ = privateDataRef.memory.deviceInterface.memory.memory.Release(privateDataRef.memory.deviceInterface)
        }
        
        _ = IOObjectRelease(privateDataRef.memory.notification)
        
        privateDataRef.dealloc(1)
    }
}

//================================================================================================
//
//	DeviceAdded
//
//	This routine is the callback for our IOServiceAddMatchingNotification.  When we get called
//	we will look at all the devices that were added and we will:
//
//	1.  Create some private data to relate to each device (in this case we use the service's name
//	    and the location ID of the device
//	2.  Submit an IOServiceAddInterestNotification of type kIOGeneralInterest for this device,
//	    using the refCon field to store a pointer to our private data.  When we get called with
//	    this interest notification, we can grab the refCon and access our private data.
//
//================================================================================================
func DeviceAdded(refCon: UnsafeMutablePointer<Void>, _ iterator: io_iterator_t) {
    var kr: kern_return_t = 0
    var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>> = nil
    var score: Int32 = 0
    var res: HRESULT = 0
    
    while case let usbDevice = IOIteratorNext(iterator) where usbDevice != 0 {
        let deviceNamePtr = UnsafeMutablePointer<io_name_t>.alloc(1)
        defer {deviceNamePtr.dealloc(1)}
        var locationID: UInt32 = 0
        
        print("Device added.")
        
        // Add some app-specific information about this device.
        // Create a buffer to hold the data.
        let privateDataRef = UnsafeMutablePointer<MyPrivateData>.alloc(1)
        bzero(privateDataRef, sizeof(MyPrivateData))
        
        // Get the USB device's name.
        kr = IORegistryEntryGetName(usbDevice, UnsafeMutablePointer(deviceNamePtr))
        if kr != KERN_SUCCESS {
            deviceNamePtr.memory.0 = 0
        }
        
        let deviceNameAsString = String.fromCString(UnsafePointer(deviceNamePtr))
        
        // Dump our data to stderr just to see what it looks like.
        print("deviceName: \(deviceNameAsString)", toStream: &stderr)
        
        // Save the device's name to our private data.
        privateDataRef.memory.deviceName = deviceNameAsString
        
        // Now, get the locationID of this device. In order to do this, we need to create an IOUSBDeviceInterface
        // for our device. This will create the necessary connections between our userland application and the
        // kernel object for the USB Device.
        kr = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
            &plugInInterface, &score)
        
        if kr != kIOReturnSuccess || plugInInterface == nil {
            print("IOCreatePlugInInterfaceForService returned 0x\(String(format: "%08x", kr)).", toStream: &stderr)
            continue
        }
        
        // Use the plugin interface to retrieve the device interface.
        res = withUnsafeMutablePointer(&privateDataRef.memory.deviceInterface) {deviceInterfacePtr in
            plugInInterface.memory.memory.QueryInterface(plugInInterface,
                CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                UnsafeMutablePointer(deviceInterfacePtr))
        }
        
        // Now done with the plugin interface.
        plugInInterface.memory.memory.Release(plugInInterface)
        
        if res != 0 || privateDataRef.memory.deviceInterface == nil {
            print("QueryInterface returned \(res).", toStream: &stderr)
            continue
        }
        
        // Now that we have the IOUSBDeviceInterface, we can call the routines in IOUSBLib.h.
        // In this case, fetch the locationID. The locationID uniquely identifies the device
        // and will remain the same, even across reboots, so long as the bus topology doesn't change.
        
        kr = privateDataRef.memory.deviceInterface.memory.memory.GetLocationID(privateDataRef.memory.deviceInterface, &locationID)
        if kr != KERN_SUCCESS {
            print("GetLocationID returned 0x\(String(format: "%08x", kr)).", toStream: &stderr)
            continue
        } else {
            print("Location ID: 0x\(locationID)\n",  toStream: &stderr)
        }
        
        privateDataRef.memory.locationID = locationID
        
        // Register for an interest notification of this device being removed. Use a reference to our
        // private data as the refCon which will be passed to the notification callback.
        kr = IOServiceAddInterestNotification(gNotifyPort,						// notifyPort
            usbDevice,						// service
            kIOGeneralInterest,				// interestType
            DeviceNotification,				// callback
            privateDataRef,					// refCon
            &privateDataRef.memory.notification)	// notification
        
        if kr != KERN_SUCCESS {
            print("IOServiceAddInterestNotification returned 0x\(String(format: "%08x", kr)).")
        }
        
        // Done with this USB device; release the reference added by IOIteratorNext
        kr = IOObjectRelease(usbDevice)
    }
}

//================================================================================================
//
//	SignalHandler
//
//	This routine will get called when we interrupt the program (usually with a Ctrl-C from the
//	command line).
//
//================================================================================================
func SignalHandler(sigraised: Int32) {
    print("\nInterrupted.", toStream: &stderr)
    
    exit(0)
}

//================================================================================================
//	main
//================================================================================================
func main(args: [String]) -> Int32 {
    var usbVendor = kMyVendorID
    var usbProduct = kMyProductID
    
    // pick up command line arguments
    if args.count > 1 {
        usbVendor = atol(args[1])
    }
    if Process.arguments.count > 2 {
        usbProduct = atol(args[2])
    }
    
    // Set up a signal handler so we can clean up when we're interrupted from the command line
    // Otherwise we stay in our run loop forever.
    let oldHandler: sig_t! = signal(SIGINT, SignalHandler)
    if unsafeBitCast(oldHandler, Int.self) == unsafeBitCast(SIG_ERR, Int.self) {
        print("Could not establish new signal handler.", toStream: &stderr)
    }
    
    print("Looking for devices matching vendor ID=\(usbVendor) and product ID=\(usbProduct).", toStream: &stderr)
    
    // Set up the matching criteria for the devices we're interested in. The matching criteria needs to follow
    // the same rules as kernel drivers: mainly it needs to follow the USB Common Class Specification, pp. 6-7.
    // See also Technical Q&A QA1076 "Tips on USB driver matching on Mac OS X"
    // <http://developer.apple.com/qa/qa2001/qa1076.html>.
    // One exception is that you can use the matching dictionary "as is", i.e. without adding any matching
    // criteria to it and it will match every IOUSBDevice in the system. IOServiceAddMatchingNotification will
    // consume this dictionary reference, so there is no need to release it later on.
    
    var matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as [NSObject: AnyObject]!	// Interested in instances of class
    // IOUSBDevice and its subclasses
    if matchingDict == nil {
        print("IOServiceMatching returned NULL.", toStream: &stderr)
        return -1
    }
    
    // We are interested in all USB devices (as opposed to USB interfaces).  The Common Class Specification
    // tells us that we need to specify the idVendor, idProduct, and bcdDevice fields, or, if we're not interested
    // in particular bcdDevices, just the idVendor and idProduct.  Note that if we were trying to match an
    // IOUSBInterface, we would need to set more values in the matching dictionary (e.g. idVendor, idProduct,
    // bInterfaceNumber and bConfigurationValue.
    
    // Create a CFNumber for the idVendor and set the value in the dictionary
    matchingDict[kUSBVendorID] = usbVendor
    
    // Create a CFNumber for the idProduct and set the value in the dictionary
    matchingDict[kUSBProductID] = usbProduct
    
    // Create a notification port and add its run loop event source to our run loop
    // This is how async notifications get set up.
    
    gNotifyPort = IONotificationPortCreate(kIOMasterPortDefault)
    let runLoopSource = IONotificationPortGetRunLoopSource(gNotifyPort).takeUnretainedValue()
    
    gRunLoop = CFRunLoopGetCurrent()
    CFRunLoopAddSource(gRunLoop, runLoopSource, kCFRunLoopDefaultMode)
    
    // Now set up a notification to be called when a device is first matched by I/O Kit.
    let _ = IOServiceAddMatchingNotification(gNotifyPort,					// notifyPort
        kIOFirstMatchNotification,	// notificationType
        matchingDict,					// matching
        DeviceAdded,					// callback
        nil,							// refCon
        &gAddedIter					// notification
    )
    
    // Iterate once to get already-present devices and arm the notification
    DeviceAdded(nil, gAddedIter)
    
    // Start the run loop. Now we'll receive notifications.
    print("Starting run loop.\n", toStream: &stderr)
    CFRunLoopRun()
    
    // We should never get here
    print("Unexpectedly back from CFRunLoopRun()!", toStream: &stderr)
    return 0
}

let ret = main(Process.arguments)
exit(ret)

