//
//  Test_VisionProApp.swift
//  Test_VisionPro
//
//  Created by Christopher Hoffmann on 8/26/24.
//  Copyright © 2024 Adobe. All rights reserved.
//

import SwiftUI
import AEPCore
import AEPServices
import AEPLifecycle
import AEPSignal
import AEPIdentity

@main
struct Test_VisionProApp: App {
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        MobileCore.setLogLevel(.trace)
        MobileCore.registerExtensions([Identity.self, Lifecycle.self]) {
            MobileCore.configureWith(appId: "staging/1b50a869c4a2/1532446f230d/launch-619c11f61f11-development")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }.onChange(of: scenePhase) { oldValue, newValue in
            switch newValue {
            case .active:
                MobileCore.lifecycleStart(additionalContextData: nil)
            case .background:
                MobileCore.lifecyclePause()
            case .inactive:
                print("Inactive scene phase")
            @unknown default:
                print("Unknown scene phase")
            }
        }

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
        }
    }
}
