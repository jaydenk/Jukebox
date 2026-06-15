//
//  Helper.swift
//  Jukebox
//
//  Created by Sasindu Jayasinghe on 26/1/2022.
//

import Foundation

class Helper {
    enum PermissionStatus {
        case closed, granted, notPrompted, denied
    }
    
    static func promptUserForConsent(for appBundleID: String) -> PermissionStatus {
        
        let target = NSAppleEventDescriptor(bundleIdentifier: appBundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        
        switch status {
        case -600:
            Log.permissions.notice("Automation target not open: \(appBundleID)")
            return .closed
        case -0:
            Log.permissions.info("Automation permission granted: \(appBundleID)")
            return .granted
        case -1744:
            Log.permissions.notice("Automation consent required but not prompted: \(appBundleID)")
            return .notPrompted
        default:
            Log.permissions.notice("Automation permission denied: \(appBundleID)")
            return .denied
        }
    }
}
