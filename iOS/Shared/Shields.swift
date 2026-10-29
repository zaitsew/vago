import FamilyControls
import ManagedSettings

/// The two shields. Both read the saved selections from the App Group.
enum VagoShields {
    /// "Work or scroll?" on the ambiguous selection. Apps of the productive selection stay open.
    static func applyAmbiguous(_ store: VagoStore = VagoStore()) {
        let ambiguous = store.selection(.ambiguous)
        let productive = store.selection(.productive)
        apply(
            to: ManagedSettingsStore(named: .ambiguous),
            applications: ambiguous.applicationTokens,
            categories: ambiguous.categoryTokens,
            webDomains: ambiguous.webDomainTokens,
            except: productive
        )
    }

    static func liftAmbiguous() {
        clear(ManagedSettingsStore(named: .ambiguous))
    }

    /// Procrastination and ambiguous apps, for the length of a focus session.
    static func applyFocus(_ store: VagoStore = VagoStore()) {
        let procrastination = store.selection(.procrastination)
        let ambiguous = store.selection(.ambiguous)
        let productive = store.selection(.productive)
        apply(
            to: ManagedSettingsStore(named: .focus),
            applications: procrastination.applicationTokens.union(ambiguous.applicationTokens),
            categories: procrastination.categoryTokens.union(ambiguous.categoryTokens),
            webDomains: procrastination.webDomainTokens.union(ambiguous.webDomainTokens),
            except: productive
        )
    }

    static func liftFocus() {
        clear(ManagedSettingsStore(named: .focus))
    }

    private static func apply(
        to store: ManagedSettingsStore,
        applications: Set<ApplicationToken>,
        categories: Set<ActivityCategoryToken>,
        webDomains: Set<WebDomainToken>,
        except productive: FamilyActivitySelection
    ) {
        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty
            ? nil : .specific(categories, except: productive.applicationTokens)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        store.shield.webDomainCategories = categories.isEmpty
            ? nil : .specific(categories, except: productive.webDomainTokens)
    }

    private static func clear(_ store: ManagedSettingsStore) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}
