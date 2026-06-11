import Foundation
import SwiftData

@Model
public final class AppSettings {
    public var retentionDays: Int
    public var refreshOnLaunch: Bool
    public var refreshOnManualCommand: Bool
    public var refreshWhileOpenMinutes: Int?
    public var openLinksInDefaultBrowser: Bool
    public var markReadOnOpen: Bool

    public init(
        retentionDays: Int = 7,
        refreshOnLaunch: Bool = true,
        refreshOnManualCommand: Bool = true,
        refreshWhileOpenMinutes: Int? = nil,
        openLinksInDefaultBrowser: Bool = true,
        markReadOnOpen: Bool = false
    ) {
        self.retentionDays = retentionDays
        self.refreshOnLaunch = refreshOnLaunch
        self.refreshOnManualCommand = refreshOnManualCommand
        self.refreshWhileOpenMinutes = refreshWhileOpenMinutes
        self.openLinksInDefaultBrowser = openLinksInDefaultBrowser
        self.markReadOnOpen = markReadOnOpen
    }
}

