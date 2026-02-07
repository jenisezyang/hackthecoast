import SwiftUI
import CoreBluetooth
import Combine
import UIKit

// MARK: - Backend Models

enum AgeBracket: String, CaseIterable, Identifiable {
    case week1  = "Less than 1 week"
    case week2  = "2 weeks"
    case week3  = "3 weeks"
    case week4  = "4 weeks"
    case month2 = "2 months"
    case month3 = "3 months"
    case month6 = "6 months"
    case month9 = "9 months"
    case year1  = "1 year"

    var id: String { rawValue }
}

enum VitalStatus: Equatable {
    case normal, warning, danger

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .danger: return .red
        }
    }
}

struct VitalRange {
    let low: Double
    let high: Double

    // Danger if out of range; Warning if within 10% of edges
    func status(for value: Double) -> VitalStatus {
        if value < low || value > high { return .danger }
        let width = max(0.0001, high - low)
        let warnBand = width * 0.10
        if value < low + warnBand || value > high - warnBand { return .warning }
        return .normal
    }

    func label(decimals: Int = 0) -> String {
        let fmt = "%.\(decimals)f–%.\(decimals)f"
        return String(format: fmt, low, high)
    }
}

struct BaselineVitals {
    let tempC: VitalRange
    let heartRateBpm: VitalRange
    let spo2: VitalRange
    let sysBP: VitalRange
    let diaBP: VitalRange
}

// Prototype baselines (replace with clinically validated ranges later)
func baseline(for bracket: AgeBracket) -> BaselineVitals {
    switch bracket {
    case .week1:
        return .init(
            tempC: .init(low: 36.5, high: 38.0),
            heartRateBpm: .init(low: 100, high: 180),
            spo2: .init(low: 95, high: 100),
            sysBP: .init(low: 60, high: 80),
            diaBP: .init(low: 30, high: 50)
        )
    case .week2, .week3, .week4:
        return .init(
            tempC: .init(low: 36.5, high: 38.0),
            heartRateBpm: .init(low: 100, high: 170),
            spo2: .init(low: 95, high: 100),
            sysBP: .init(low: 65, high: 85),
            diaBP: .init(low: 35, high: 55)
        )
    case .month2, .month3:
        return .init(
            tempC: .init(low: 36.5, high: 38.0),
            heartRateBpm: .init(low: 90, high: 160),
            spo2: .init(low: 95, high: 100),
            sysBP: .init(low: 70, high: 95),
            diaBP: .init(low: 40, high: 60)
        )
    case .month6, .month9, .year1:
        return .init(
            tempC: .init(low: 36.5, high: 38.0),
            heartRateBpm: .init(low: 80, high: 150),
            spo2: .init(low: 95, high: 100),
            sysBP: .init(low: 75, high: 100),
            diaBP: .init(low: 45, high: 65)
        )
    }
}

enum BabyCondition: String, CaseIterable, Identifiable {
    case premature = "Premature"
    case lowBirthWeight = "Low birth weight"
    case jaundice = "Jaundice"
    case colic = "Colic"
    case reflux = "Reflux (GERD)"
    case congenitalHeart = "Congenital heart condition"
    case respiratoryIssues = "Respiratory issues"
    case infectionRisk = "Infection risk"
    case apnea = "Apnea episodes"
    case seizures = "Seizure disorder"

    var id: String { rawValue }
}

// MARK: - Date Helpers

private func daysBetween(_ start: Date, _ end: Date) -> Int {
    let cal = Calendar.current
    let s = cal.startOfDay(for: start)
    let e = cal.startOfDay(for: end)
    return cal.dateComponents([.day], from: s, to: e).day ?? 0
}

private func bracketFromBirthday(_ birthday: Date) -> AgeBracket {
    let days = max(0, daysBetween(birthday, Date()))
    if days <= 6 { return .week1 }
    if days <= 13 { return .week2 }
    if days <= 20 { return .week3 }
    if days <= 27 { return .week4 }
    if days <= 60 { return .month2 }
    if days <= 90 { return .month3 }
    if days <= 180 { return .month6 }
    if days <= 270 { return .month9 }
    return .year1
}

// MARK: - Root Router (Setup -> Tabs)

struct ContentView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @AppStorage("babyName") private var babyName = ""
    @AppStorage("birthdayEpoch") private var birthdayEpoch: Double = Date().timeIntervalSince1970
    @AppStorage("conditionsCSV") private var conditionsCSV = ""

    private var birthday: Date { Date(timeIntervalSince1970: birthdayEpoch) }
    private var conditionStrings: Set<String> {
        Set(conditionsCSV.split(separator: ",").map { String($0) })
    }

    var body: some View {
        if hasCompletedSetup {
            MainTabView(babyName: babyName, birthday: birthday, conditions: conditionStrings)
        } else {
            SetupView(
                hasCompletedSetup: $hasCompletedSetup,
                babyName: $babyName,
                birthdayEpoch: $birthdayEpoch,
                conditionsCSV: $conditionsCSV
            )
        }
    }
}

// MARK: - Main Tabs (Dashboard + Hospitals + Profile)

struct MainTabView: View {
    let babyName: String
    let birthday: Date
    let conditions: Set<String>

    var body: some View {
        TabView {
            DashboardView(babyName: babyName, birthday: birthday, conditions: conditions)
                .tabItem { Label("Dashboard", systemImage: "waveform.path.ecg") }

            HospitalsView()
                .tabItem { Label("Hospitals", systemImage: "cross.case.fill") }

            ProfileView(babyName: babyName, birthday: birthday, conditions: conditions)
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}

// MARK: - Setup Screen (SCROLLABLE)

struct SetupView: View {
    @Binding var hasCompletedSetup: Bool
    @Binding var babyName: String
    @Binding var birthdayEpoch: Double
    @Binding var conditionsCSV: String

    @State private var birthday: Date = Date()
    @State private var selected = Set<BabyCondition>()
    @State private var showConditions = false

    private var ageBracket: AgeBracket { bracketFromBirthday(birthday) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.92, green: 0.96, blue: 1.0), Color(red: 1.0, green: 0.94, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lullis")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Set up your baby’s profile")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)

                    card(title: "Baby Profile") {
                        VStack(alignment: .leading, spacing: 12) {
                            labeled("Name") {
                                TextField("Enter name", text: $babyName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            labeled("Birthday") {
                                DatePicker(
                                    "",
                                    selection: $birthday,
                                    in: ...Date(),
                                    displayedComponents: [.date]
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                            }

                            HStack {
                                Text("Age group").foregroundColor(.secondary)
                                Spacer()
                                Text(ageBracket.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.7))
                                    .cornerRadius(10)
                            }
                        }
                    }

                    card(title: "Conditions") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation { showConditions.toggle() }
                            } label: {
                                HStack {
                                    Text(selected.isEmpty ? "Select health conditions" : "\(selected.count) selected")
                                        .foregroundColor(selected.isEmpty ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: showConditions ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if showConditions {
                                Divider().opacity(0.5)
                                ForEach(BabyCondition.allCases) { c in
                                    MultipleChoiceRow(
                                        title: c.rawValue,
                                        isSelected: selected.contains(c)
                                    ) {
                                        if selected.contains(c) { selected.remove(c) }
                                        else { selected.insert(c) }
                                    }
                                }
                            }
                        }
                    }

                    card(title: "Vitals monitored") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Heart rate")
                            Text("• Oxygen levels (SpO₂)")
                            Text("• Body temperature")
                            Text("• Blood pressure (systolic/diastolic)")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }

                    Button {
                        birthdayEpoch = birthday.timeIntervalSince1970
                        conditionsCSV = selected.map { $0.rawValue }.sorted().joined(separator: ",")
                        hasCompletedSetup = true
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(babyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(14)
                    }
                    .disabled(babyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 6)
                }
                .padding(16)
                .padding(.bottom, 140) // ✅ extra space
            }
            .scrollIndicators(.visible)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 20) } // ✅ reserves space above tab bar
        }
        .onAppear {
            birthday = Date(timeIntervalSince1970: birthdayEpoch)
            let set = Set(conditionsCSV.split(separator: ",").map { String($0) })
            selected = Set(BabyCondition.allCases.filter { set.contains($0.rawValue) })
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(Color.white.opacity(0.75))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            content()
        }
    }
}

struct MultipleChoiceRow: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                Text(title).foregroundColor(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard Screen (SCROLLABLE)

struct DashboardView: View {
    let babyName: String
    let birthday: Date
    let conditions: Set<String>

    @StateObject private var bt: BluetoothManager

    init(babyName: String, birthday: Date, conditions: Set<String>) {
        self.babyName = babyName
        self.birthday = birthday
        self.conditions = conditions
        _bt = StateObject(wrappedValue: BluetoothManager())
    }

    private var ageDays: Int { max(0, daysBetween(birthday, Date())) }
    private var bracket: AgeBracket { bracketFromBirthday(birthday) }
    private var base: BaselineVitals { baseline(for: bracket) }

    private var tempStatus: VitalStatus { base.tempC.status(for: bt.temperature) }
    private var hrStatus: VitalStatus { base.heartRateBpm.status(for: bt.heartRate) }
    private var spo2Status: VitalStatus { base.spo2.status(for: bt.spo2) }
    private var sysStatus: VitalStatus { base.sysBP.status(for: bt.bpSys) }
    private var diaStatus: VitalStatus { base.diaBP.status(for: bt.bpDia) }

    private var anyDanger: Bool {
        [tempStatus, hrStatus, spo2Status, sysStatus, diaStatus].contains(.danger)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.95, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    connectionRow

                    VitalCard(
                        title: "Body Temperature",
                        value: String(format: "%.1f °C", bt.temperature),
                        rangeText: base.tempC.label(decimals: 1),
                        status: tempStatus,
                        icon: "thermometer"
                    )

                    VitalCard(
                        title: "Heart Rate",
                        value: "\(Int(bt.heartRate)) bpm",
                        rangeText: base.heartRateBpm.label(decimals: 0),
                        status: hrStatus,
                        icon: "heart.fill"
                    )

                    VitalCard(
                        title: "Oxygen Level (SpO₂)",
                        value: "\(Int(bt.spo2))%",
                        rangeText: base.spo2.label(decimals: 0),
                        status: spo2Status,
                        icon: "waveform.path.ecg"
                    )

                    VitalCard(
                        title: "Blood Pressure",
                        value: "\(Int(bt.bpSys)) / \(Int(bt.bpDia)) mmHg",
                        rangeText: "SYS \(base.sysBP.label()) • DIA \(base.diaBP.label())",
                        status: maxStatus(sysStatus, diaStatus),
                        icon: "drop.fill"
                    )

                    if anyDanger {
                        Button {
                            HospitalsView.openHospitalsAppleMaps()
                        } label: {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                Text("Locate the nearest hospital")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(14)
                            .padding(.horizontal, 16)
                        }
                    }

                    Button {
                        bt.isConnected ? bt.disconnect() : bt.startScanning()
                    } label: {
                        Text(bt.isConnected ? "Disconnect Device" : "Connect Device")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bt.isConnected ? Color.red : Color.blue)
                            .cornerRadius(14)
                            .padding(.horizontal, 16)
                    }

                }
                .padding(.top, 10)
                .padding(.bottom, 140) // ✅ extra space
            }
            .scrollIndicators(.visible)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 20) } // ✅ reserves space above tab bar
        }
    }

    private func maxStatus(_ a: VitalStatus, _ b: VitalStatus) -> VitalStatus {
        if a == .danger || b == .danger { return .danger }
        if a == .warning || b == .warning { return .warning }
        return .normal
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Lullis")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    Text(babyName).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Age: \(ageDays) days")
                        .font(.subheadline.weight(.semibold))
                    Text(bracket.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.white.opacity(0.7))
                .cornerRadius(12)
            }

            HStack(spacing: 10) {
                chip("Birthday", birthday.formatted(date: .abbreviated, time: .omitted))
                chip("Conditions", conditions.isEmpty ? "None" : "\(conditions.count)")
            }

            if !conditions.isEmpty {
                Text(conditions.sorted().joined(separator: " • "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var connectionRow: some View {
        HStack(spacing: 8) {
            Circle().fill(bt.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(bt.isConnected ? "Device Connected" : "Disconnected")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.7))
        .cornerRadius(12)
    }
}

struct VitalCard: View {
    let title: String
    let value: String
    let rangeText: String?
    let status: VitalStatus
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.20))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(status.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundColor(.secondary)
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                if let rangeText {
                    Text("Normal: \(rangeText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(status.color)
                .frame(width: 14, height: 14)
        }
        .padding(16)
        .background(Color.white.opacity(0.75))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
    }
}

// MARK: - Hospitals Tab (always accessible)

struct HospitalsView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.92, green: 0.96, blue: 1.0), Color(red: 1.0, green: 0.94, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Nearby Care")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.top, 10)

                    Text("Search anytime (not only during alerts).")
                        .foregroundColor(.secondary)

                    Button {
                        HospitalsView.openHospitalsAppleMaps()
                    } label: {
                        HStack {
                            Image(systemName: "cross.case.fill")
                            Text("Find nearby hospitals")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                    }

                    Button {
                        HospitalsView.openChildHospitalsAppleMaps()
                    } label: {
                        HStack {
                            Image(systemName: "stethoscope")
                            Text("Find children’s hospitals")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(14)
                    }

                    Spacer(minLength: 10)
                }
                .padding(16)
                .padding(.bottom, 140) // ✅ extra space
            }
            .scrollIndicators(.visible)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 20) } // ✅ reserves space above tab bar
        }
    }

    static func openHospitalsAppleMaps() {
        if let url = URL(string: "http://maps.apple.com/?q=hospital") {
            UIApplication.shared.open(url)
        }
    }

    static func openChildHospitalsAppleMaps() {
        if let url = URL(string: "http://maps.apple.com/?q=children%20hospital") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Profile Tab

struct ProfileView: View {
    let babyName: String
    let birthday: Date
    let conditions: Set<String>

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.95, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Profile")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.top, 10)

                    infoCard(title: "Baby") { Text(babyName).font(.headline) }
                    infoCard(title: "Birthday") { Text(birthday.formatted(date: .abbreviated, time: .omitted)) }

                    infoCard(title: "Conditions") {
                        if conditions.isEmpty {
                            Text("None").foregroundColor(.secondary)
                        } else {
                            Text(conditions.sorted().joined(separator: " • "))
                        }
                    }

                    Button(role: .destructive) {
                        UserDefaults.standard.set(false, forKey: "hasCompletedSetup")
                    } label: {
                        Text("Reset Setup (dev)")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .background(Color.white.opacity(0.75))
                    .cornerRadius(14)

                    Spacer(minLength: 10)
                }
                .padding(16)
                .padding(.bottom, 140) // ✅ extra space
            }
            .scrollIndicators(.visible)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 20) } // ✅ reserves space above tab bar
        }
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            content()
        }
        .padding(16)
        .background(Color.white.opacity(0.75))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Bluetooth Manager (Prototype, no Timer -> avoids MainActor Sendable issues)
//
// Expected strings from Arduino later:
// "TEMP:36.9,HR:132,SPO2:98,BPSYS:72,BPDIA:44"

@MainActor
final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isConnected = false

    @Published var temperature: Double = 36.8
    @Published var heartRate: Double = 130
    @Published var spo2: Double = 98
    @Published var bpSys: Double = 72
    @Published var bpDia: Double = 44

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func disconnect() {
        if let p = peripheral { centralManager.cancelPeripheralConnection(p) }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn { isConnected = false }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        if name.contains("Arduino") || name.contains("Lullis") || name.contains("101") {
            self.peripheral = peripheral
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        self.peripheral = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for c in characteristics where c.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        if let str = String(data: data, encoding: .utf8) {
            parseIncoming(str)
        }
    }

    private func parseIncoming(_ str: String) {
        let parts = str
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ",")

        for part in parts {
            let kv = part.components(separatedBy: ":")
            guard kv.count == 2 else { continue }
            let key = kv[0].uppercased()
            let value = kv[1]

            switch key {
            case "TEMP":
                if let v = Double(value) { temperature = v }
            case "HR":
                if let v = Double(value) { heartRate = v }
            case "SPO2":
                if let v = Double(value) { spo2 = v }
            case "BPSYS":
                if let v = Double(value) { bpSys = v }
            case "BPDIA":
                if let v = Double(value) { bpDia = v }
            default:
                break
            }
        }
    }
}

