import SwiftUI
import Combine
import UIKit

// MARK: - Theme

private let gemini = GeminiService(apiKey: "AIzaSyBoz2Pg3xDHhy5ajAmf9Nv6Xv-mwdbeY2g")


enum LullisTheme {
    static let primary = Color(red: 0.33, green: 0.29, blue: 0.95)     // purple-ish
    static let bgTop   = Color(red: 0.95, green: 0.97, blue: 1.00)
    static let bgBot   = Color(red: 1.00, green: 0.97, blue: 0.98)

    static let cardFill = Color.white.opacity(0.86)
    static let shadow = Color.black.opacity(0.08)

    // #CCCCFF + a few slightly darker shades (same hue family)
    static let purple1 = Color(red: 204/255, green: 204/255, blue: 255/255) // #CCCCFF
    static let purple2 = Color(red: 184/255, green: 184/255, blue: 255/255)
    static let purple3 = Color(red: 163/255, green: 163/255, blue: 255/255)
    static let purple4 = Color(red: 143/255, green: 143/255, blue: 255/255)
}

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

enum Sex: String, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    var id: String { rawValue }
}

enum VitalStatus: Equatable {
    case normal, warning, danger

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
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

// MARK: - Vital Detail Selection

enum VitalID: String, Identifiable {
    case temp, hr, spo2, bp
    var id: String { rawValue }
}

// MARK: - Demo Vitals Store (NO BLUETOOTH)

@MainActor
final class DemoVitalsStore: ObservableObject {
    @Published var temperature: Double = 36.8
    @Published var heartRate: Double = 130
    @Published var spo2: Double = 98
    @Published var bpSys: Double = 72
    @Published var bpDia: Double = 44

    enum DemoAction {
        case rollover
        case hypoxia
        case fever
        case clearDemo
        case heartbeatTick(Int)
    }

    func apply(_ action: DemoAction, blockTickWhenDanger: Bool, overallStatus: VitalStatus) {
        switch action {
        case .clearDemo:
            temperature = 36.8
            heartRate = 130
            spo2 = 98
            bpSys = 72
            bpDia = 44

        case .rollover:
            // Make it clearly "danger" and KEEP it there until Clear Demo
            heartRate = 210
            spo2 = 82
            bpSys = 55
            bpDia = 28

        case .hypoxia:
            spo2 = 78
            heartRate = 170

        case .fever:
            temperature = 39.6
            heartRate = 165

        case .heartbeatTick(let t):
            if blockTickWhenDanger, overallStatus == .danger { return }
            temperature = 36.6 + Double(t % 6) * 0.05
            heartRate = 128 + Double((t % 8) - 4) * 1.5
            spo2 = 98 + Double((t % 6) - 3) * 0.3
            bpSys = 72 + Double((t % 4) - 2)
            bpDia = 44 + Double((t % 4) - 2)
        }
    }
}

// MARK: - Root Router (Setup -> Tabs)

struct ContentView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @AppStorage("babyName") private var babyName = ""
    @AppStorage("birthdayEpoch") private var birthdayEpoch: Double = Date().timeIntervalSince1970
    @AppStorage("conditionsCSV") private var conditionsCSV = ""
    @AppStorage("babySex") private var babySex: String = Sex.male.rawValue
    @AppStorage("babyWeightKg") private var babyWeightKg: Double = 3.5

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

    @AppStorage("babySex") private var babySex: String = Sex.male.rawValue
    @AppStorage("babyWeightKg") private var babyWeightKg: Double = 3.5

    @State private var weightText: String = "3.5"
    @State private var selectedSex: Sex = .male

    private var ageBracket: AgeBracket { bracketFromBirthday(birthday) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [LullisTheme.bgTop, LullisTheme.bgBot],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lullis")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.88))
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
                                DatePicker("", selection: $birthday, in: ...Date(), displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }

                            labeled("Sex") {
                                Picker("", selection: $selectedSex) {
                                    ForEach(Sex.allCases) { s in
                                        Text(s.rawValue).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            labeled("Weight (kg)") {
                                TextField("e.g., 3.5", text: $weightText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: weightText) { _, newValue in
                                        let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                                        if let v = Double(cleaned) { babyWeightKg = v }
                                    }
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
                        babySex = selectedSex.rawValue
                        let cleaned = weightText.replacingOccurrences(of: ",", with: ".")
                        babyWeightKg = Double(cleaned) ?? babyWeightKg
                        hasCompletedSetup = true
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(babyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : LullisTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: LullisTheme.primary.opacity(0.25), radius: 16, x: 0, y: 10)
                    }
                    .disabled(babyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer(minLength: 10)
                }
                .padding(16)
            }
            .scrollIndicators(.visible)
        }
        .onAppear {
            birthday = Date(timeIntervalSince1970: birthdayEpoch)
            let set = Set(conditionsCSV.split(separator: ",").map { String($0) })
            selected = Set(BabyCondition.allCases.filter { set.contains($0.rawValue) })
            selectedSex = Sex(rawValue: babySex) ?? .male
            weightText = String(format: "%.1f", babyWeightKg)
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(LullisTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: LullisTheme.shadow, radius: 12, x: 0, y: 6)
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
                    .foregroundColor(isSelected ? LullisTheme.primary : .secondary)
                Text(title).foregroundColor(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard Screen (DEMO ONLY)

struct DashboardView: View {
    let babyName: String
    let birthday: Date
    let conditions: Set<String>

    @StateObject private var demo = DemoVitalsStore()
    @State private var selectedVital: VitalID?

    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var ageDays: Int { max(0, daysBetween(birthday, Date())) }
    private var bracket: AgeBracket { bracketFromBirthday(birthday) }
    private var base: BaselineVitals { baseline(for: bracket) }

    private var tempStatus: VitalStatus { base.tempC.status(for: demo.temperature) }
    private var hrStatus: VitalStatus { base.heartRateBpm.status(for: demo.heartRate) }
    private var spo2Status: VitalStatus { base.spo2.status(for: demo.spo2) }
    private var sysStatus: VitalStatus { base.sysBP.status(for: demo.bpSys) }
    private var diaStatus: VitalStatus { base.diaBP.status(for: demo.bpDia) }

    private var overallStatus: VitalStatus {
        let statuses = [tempStatus, hrStatus, spo2Status, sysStatus, diaStatus]
        if statuses.contains(.danger) { return .danger }
        if statuses.contains(.warning) { return .warning }
        return .normal
    }

    private var anyDanger: Bool { overallStatus == .danger }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [LullisTheme.bgTop, LullisTheme.bgBot],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerRow

                    StatusBanner(status: overallStatus)

                    LazyVGrid(columns: columns, spacing: 12) {
                        VitalTile(
                            icon: "heart.fill",
                            iconTint: LullisTheme.purple4,
                            title: "Heart Rate",
                            valueBig: "\(Int(demo.heartRate))",
                            unit: "BPM",
                            sparkColor: LullisTheme.purple4
                        ) { selectedVital = .hr }

                        VitalTile(
                            icon: "wind",
                            iconTint: LullisTheme.purple3,
                            title: "Oxygen (SpO₂)",
                            valueBig: "\(Int(demo.spo2))",
                            unit: "%",
                            sparkColor: LullisTheme.purple3
                        ) { selectedVital = .spo2 }

                        VitalTile(
                            icon: "thermometer",
                            iconTint: LullisTheme.purple2,
                            title: "Body Temp",
                            valueBig: String(format: "%.1f", demo.temperature),
                            unit: "°C",
                            sparkColor: LullisTheme.purple2
                        ) { selectedVital = .temp }

                        VitalTile(
                            icon: "drop.fill",
                            iconTint: LullisTheme.purple1,
                            title: "Blood Pressure",
                            valueBig: "\(Int(demo.bpSys))/\(Int(demo.bpDia))",
                            unit: "mmHg",
                            sparkColor: LullisTheme.purple1
                        ) { selectedVital = .bp }
                    }

                    // SIMULATE CONDITIONS (PERSIST UNTIL CLEAR)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SIMULATE CONDITIONS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            SmallActionPill(icon: "arrow.triangle.2.circlepath", label: "Rollover") {
                                demo.apply(.rollover, blockTickWhenDanger: true, overallStatus: overallStatus)
                            }
                            SmallActionPill(icon: "exclamationmark.triangle", label: "Hypoxia") {
                                demo.apply(.hypoxia, blockTickWhenDanger: true, overallStatus: overallStatus)
                            }
                            SmallActionPill(icon: "thermometer.high", label: "Fever") {
                                demo.apply(.fever, blockTickWhenDanger: true, overallStatus: overallStatus)
                            }
                        }

                        SmallActionPill(icon: "arrow.counterclockwise", label: "Clear Demo") {
                            demo.apply(.clearDemo, blockTickWhenDanger: true, overallStatus: overallStatus)
                        }
                    }
                    .padding(.top, 4)

                    if anyDanger {
                        DangerCard {
                            HospitalsView.openHospitalsAppleMaps()
                        }
                    }

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.visible)
        }
        .onReceive(timer) { _ in
            tick += 1
            demo.apply(.heartbeatTick(tick), blockTickWhenDanger: true, overallStatus: overallStatus)
        }
        .sheet(item: $selectedVital) { id in
            switch id {
            case .temp:
                VitalDetailSheet(
                    title: "Body Temperature",
                    currentValue: String(format: "%.1f °C", demo.temperature),
                    primaryLabel: "Typical range",
                    primaryRange: base.tempC,
                    secondaryLabel: nil,
                    secondaryRange: nil,
                    status: tempStatus,
                    ageBracket: bracket,
                    conditions: conditions
                )
            case .hr:
                VitalDetailSheet(
                    title: "Heart Rate",
                    currentValue: "\(Int(demo.heartRate)) bpm",
                    primaryLabel: "Typical range",
                    primaryRange: base.heartRateBpm,
                    secondaryLabel: nil,
                    secondaryRange: nil,
                    status: hrStatus,
                    ageBracket: bracket,
                    conditions: conditions
                )
            case .spo2:
                VitalDetailSheet(
                    title: "Oxygen Level (SpO₂)",
                    currentValue: "\(Int(demo.spo2))%",
                    primaryLabel: "Typical range",
                    primaryRange: base.spo2,
                    secondaryLabel: nil,
                    secondaryRange: nil,
                    status: spo2Status,
                    ageBracket: bracket,
                    conditions: conditions
                )
            case .bp:
                VitalDetailSheet(
                    title: "Blood Pressure",
                    currentValue: "\(Int(demo.bpSys)) / \(Int(demo.bpDia)) mmHg",
                    primaryLabel: "Systolic (SYS) typical range",
                    primaryRange: base.sysBP,
                    secondaryLabel: "Diastolic (DIA) typical range",
                    secondaryRange: base.diaBP,
                    status: maxStatus(sysStatus, diaStatus),
                    ageBracket: bracket,
                    conditions: conditions
                )
            }
        }
    }

    private func maxStatus(_ a: VitalStatus, _ b: VitalStatus) -> VitalStatus {
        if a == .danger || b == .danger { return .danger }
        if a == .warning || b == .warning { return .warning }
        return .normal
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(babyName.isEmpty ? "Baby" : babyName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.88))

                Text("\(ageDays) days old")
                    .foregroundColor(.secondary)

                if !conditions.isEmpty {
                    Text(conditions.sorted().first ?? "")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.75))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Learning")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(LullisTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(LullisTheme.primary.opacity(0.12))
                        .clipShape(Capsule())

                    Image(systemName: "gearshape")
                        .foregroundColor(.secondary)
                }

                Text(bracket.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Circle().fill(Color.orange)
                        .frame(width: 10, height: 10)
                    Text("Demo Mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Status Banner

struct StatusBanner: View {
    let status: VitalStatus

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(tint)
                    .font(.system(size: 18, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.headline)
                    .foregroundColor(tint)
                Text(subText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: LullisTheme.shadow, radius: 10, x: 0, y: 6)
    }

    private var tint: Color {
        status.color
    }

    private var titleText: String {
        switch status {
        case .normal: return "Vitals Normal"
        case .warning: return "Vitals Warning"
        case .danger: return "Potential Emergency"
        }
    }

    private var subText: String {
        switch status {
        case .normal: return "Readings are within typical ranges."
        case .warning: return "Near the edge of typical ranges."
        case .danger: return "Immediate attention may be needed."
        }
    }
}

// MARK: - Vital Tile (Grid card)

struct VitalTile: View {
    let icon: String
    let iconTint: Color
    let title: String
    let valueBig: String
    let unit: String
    let sparkColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle().fill(iconTint.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .foregroundColor(iconTint)
                            .font(.system(size: 18, weight: .bold))
                    }
                    Spacer()
                }

                Text(title)
                    .foregroundColor(.secondary)
                    .font(.subheadline.weight(.semibold))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(valueBig)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.88))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                SparkLine(color: sparkColor)
                    .frame(height: 22)
                    .opacity(0.55)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LullisTheme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: LullisTheme.shadow, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct SparkLine: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.70))
                p.addCurve(to: CGPoint(x: w * 0.25, y: h * 0.45),
                           control1: CGPoint(x: w * 0.10, y: h * 0.85),
                           control2: CGPoint(x: w * 0.15, y: h * 0.20))
                p.addCurve(to: CGPoint(x: w * 0.55, y: h * 0.80),
                           control1: CGPoint(x: w * 0.35, y: h * 0.75),
                           control2: CGPoint(x: w * 0.45, y: h * 1.05))
                p.addCurve(to: CGPoint(x: w * 0.85, y: h * 0.35),
                           control1: CGPoint(x: w * 0.65, y: h * 0.60),
                           control2: CGPoint(x: w * 0.75, y: h * 0.05))
                p.addLine(to: CGPoint(x: w, y: h * 0.55))
            }
            .stroke(color, lineWidth: 3)
        }
    }
}

// MARK: - Small Action Pills

struct SmallActionPill: View {
    let icon: String
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.black.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: LullisTheme.shadow, radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Danger Card

struct DangerCard: View {
    let onLocate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .bold))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Potential Emergency")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text("Vitals indicate immediate attention is needed.")
                        .foregroundColor(.white.opacity(0.9))
                        .font(.subheadline)
                }
                Spacer()
            }

            Button(action: onLocate) {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                    Text("Locate Nearest Hospital")
                        .font(.headline)
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(16)
        .background(Color.red.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.red.opacity(0.22), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Vital Detail Sheet

// VitalDetailSheet (drop-in replacement)
// Put this in ContentView.swift replacing your existing VitalDetailSheet.
// Requires: import SwiftUI, import Combine, import UIKit (Combine only needed elsewhere; fine to keep)

import SwiftUI

struct VitalDetailSheet: View {
    let title: String
    let currentValue: String

    let primaryLabel: String
    let primaryRange: VitalRange

    let secondaryLabel: String?
    let secondaryRange: VitalRange?

    let status: VitalStatus
    let ageBracket: AgeBracket
    let conditions: Set<String>

    // ✅ pass these in from DashboardView/Profile storage
    let sex: String
    let weightKg: Double

    // AI state
    @State private var aiText: String = ""
    @State private var aiLoading: Bool = false
    @State private var aiError: String?

    // cache per vital so it doesn’t spam requests when sheet reopens quickly
    @State private var lastPromptHash: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(currentValue)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(status.color)

                    Text("Comparison group: \(ageBracket.rawValue)")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    rangeCard(label: primaryLabel,
                              value: primaryRange.label(decimals: title == "Body Temperature" ? 1 : 0))

                    if let secondaryLabel, let secondaryRange {
                        rangeCard(label: secondaryLabel,
                                  value: secondaryRange.label(decimals: 0))
                    }

                    // ✅ AI Personalized explanation block (this is the new part)
                    aiCard

                    if !conditions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Health context").font(.headline)
                            Text("Selected conditions may require closer monitoring:")
                                .foregroundColor(.secondary)
                            Text(conditions.sorted().joined(separator: " • "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.10))
                        .cornerRadius(14)
                    }

                    Text("Note: This is informational and not a diagnosis.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.visible)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadAIIfNeeded()
        }
    }

    // MARK: - AI UI

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Personalized explanation")
                    .font(.headline)
                Spacer()
                if aiLoading {
                    ProgressView().scaleEffect(0.9)
                }
            }

            if let aiError {
                Text(aiError)
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                Button("Try again") {
                    Task { await loadAI(force: true) }
                }
                .font(.subheadline.weight(.semibold))
            } else if !aiText.isEmpty {
                Text(aiText)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                Text("Generating a brief explanation…")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(status.color.opacity(0.12))
        .cornerRadius(14)
    }

    // MARK: - Helpers

    private func rangeCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.85))
        .cornerRadius(14)
    }

    // MARK: - AI Prompt + Load

    private func makePrompt() -> String {
        let conditionText = conditions.isEmpty ? "None" : conditions.sorted().joined(separator: ", ")

        return """
        You are a calm pediatric vitals explainer. Write 2–4 short sentences. No diagnosis. Avoid alarmist language.

        Explain what the reading means compared to typical ranges for the baby's age group.
        Mention the selected conditions only if it changes how cautiously to interpret or monitor.

        Vital: \(title)
        Reading: \(currentValue)
        Status: \(statusLabel)
        Age group: \(ageBracket.rawValue)
        Sex: \(sex)
        Weight: \(String(format: "%.1f", weightKg)) kg
        Conditions: \(conditionText)
        """
    }

    private var statusLabel: String {
        switch status {
        case .normal: return "normal"
        case .warning: return "warning"
        case .danger: return "danger"
        }
    }

    private func loadAIIfNeeded() async {
        await loadAI(force: false)
    }

    private func loadAI(force: Bool) async {
        let prompt = makePrompt()
        let hash = prompt.hashValue

        if !force, lastPromptHash == hash, !aiText.isEmpty { return }
        lastPromptHash = hash

        aiLoading = true
        aiError = nil

        do {
            let text = try await GeminiService.shared.generate(prompt: prompt)
            aiText = text
        } catch {
            aiError = "Could not generate explanation."
            aiText = ""
        }

        aiLoading = false
    }
}

// MARK: - Hospitals Tab

struct HospitalsView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [LullisTheme.bgTop, LullisTheme.bgBot],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Nearby Care")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.top, 10)

                    Text("Search for hospitals near you")
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
                        .padding(.vertical, 16)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                        .padding(.vertical, 16)
                        .background(LullisTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Spacer(minLength: 10)
                }
                .padding(16)
            }
            .scrollIndicators(.visible)
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

func avatarAssetName(for sexRaw: String) -> String {
    let sex = Sex(rawValue: sexRaw) ?? .male
    switch sex {
    case .male: return "avatar_male"
    case .female: return "avatar_female"
    }
}

// MARK: - Profile Tab (2-up grid + stacked condition pills)

struct ProfileView: View {
    let babyName: String
    let birthday: Date
    let conditions: Set<String>

    @AppStorage("babySex") private var babySex: String = Sex.male.rawValue
    @AppStorage("babyWeightKg") private var babyWeightKg: Double = 3.5

    private let twoCols = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var ageText: String {
        let days = max(0, daysBetween(birthday, Date()))
        if days < 30 { return "\(days) days" }
        let months = days / 30
        if months < 12 { return "\(months) months" }
        return "\(months / 12) years"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [LullisTheme.bgTop, LullisTheme.bgBot],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Profile")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.top, 10)

                    // Avatar card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Avatar")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Image(avatarAssetName(for: babySex))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 4))
                            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
                    }
                    .padding(16)
                    .background(LullisTheme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: LullisTheme.shadow, radius: 12, x: 0, y: 6)

                    // Name/Age + Weight/Sex as 2-up grid
                    LazyVGrid(columns: twoCols, spacing: 12) {
                        infoCard(title: "Name") { Text(babyName).font(.headline) }
                        infoCard(title: "Age") { Text(ageText).font(.headline) }
                        infoCard(title: "Weight") { Text(String(format: "%.1f kg", babyWeightKg)).font(.headline) }
                        infoCard(title: "Sex") { Text(babySex).font(.headline) }
                    }

                    Text("Conditions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 6)

                    if conditions.isEmpty {
                        ConditionPill(text: "None", tint: LullisTheme.purple1)
                    } else {
                        ForEach(conditions.sorted(), id: \.self) { c in
                            ConditionPill(text: c, tint: LullisTheme.purple1)
                        }
                    }

                    Button(role: .destructive) {
                        UserDefaults.standard.set(false, forKey: "hasCompletedSetup")
                    } label: {
                        Text("Reset Setup (dev)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(Color.white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: LullisTheme.shadow, radius: 12, x: 0, y: 6)

                    Spacer(minLength: 10)
                }
                .padding(16)
            }
            .scrollIndicators(.visible)
        }
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            content()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
        .padding(16)
        .background(LullisTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: LullisTheme.shadow, radius: 12, x: 0, y: 6)
    }
}

struct ConditionPill: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(tint)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black.opacity(0.82))
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.86))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: LullisTheme.shadow, radius: 10, x: 0, y: 6)
    }
}

// MARK: - InfoCard (kept)

struct InfoCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(red: 0.93, green: 0.95, blue: 1.0).opacity(0.9))
            .overlay(
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .foregroundColor(LullisTheme.primary)
                            .font(.system(size: 18, weight: .bold))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.black.opacity(0.85))
                        Text(message)
                            .foregroundColor(LullisTheme.primary.opacity(0.85))
                            .font(.subheadline)
                    }

                    Spacer()
                }
                .padding(14)
            )
    }
}

