import SwiftUI

struct ParkingRecordListView: View {
    @ObservedObject var store: ParkingFloorStore
    let lotID: UUID
    let groupID: ParkingRecordGroup.ID?
    var onSelect: ((UUID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showAllFloors = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var showingFloorPicker = false

    private var lot: ParkingLotRecord? { store.lots.first { $0.id == lotID } }
    private var selectedParkingIDs: Set<UUID> {
        Set(records.filter { selection.contains($0.id) && $0.isAutomotive }.map(\.id))
    }
    private var records: [ParkingPointRecord] {
        guard let lot else { return [] }
        if let groupID, !showAllFloors {
            return ParkingRecordGroup.make(lots: [lot], mode: store.floorMode).first { $0.id == groupID }?.records ?? []
        }
        return lot.points.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if groupID != nil {
                    Section {
                        Picker(String(localized: "停車記錄"), selection: $showAllFloors) {
                            Text(String(localized: "此樓層")).tag(false)
                            Text(String(localized: "所有樓層")).tag(true)
                        }.pickerStyle(.segmented)
                    }
                }
                Section {
                    ForEach(records) { point in
                        if selecting {
                            recordRow(point).tag(point.id)
                                .accessibilityIdentifier("parkingRecord-\(point.id)")
                        } else if let onSelect {
                            Button {
                                onSelect(point.id)
                                dismiss()
                            } label: { recordRow(point) }
                            .buttonStyle(.automatic)
                            .accessibilityIdentifier("parkingRecord-\(point.id)")
                        } else {
                            NavigationLink {
                                ParkingPointDiagnosticsView(pointID: point.id).environmentObject(store)
                            } label: { recordRow(point) }
                        }
                    }
                } header: {
                    Text(String(format: String(localized: "%d 次記錄"), records.count))
                }
            }
            .environment(\.editMode, .constant(selecting ? .active : .inactive))
            .navigationTitle(lot?.preferredDisplayName ?? String(localized: "停車記錄"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "關閉")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? String(localized: "完成") : String(localized: "選取")) {
                        withAnimation(.smooth) { selecting.toggle() }
                        selection = []
                    }.accessibilityIdentifier("selectParkingRecords")
                }
                if selecting {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            showingFloorPicker = true
                        } label: {
                            Label(String(localized: "修正樓層"), systemImage: "building.2")
                        }
                        .disabled(selectedParkingIDs.isEmpty)
                        .accessibilityIdentifier("correctSelectedFloors")
                    }
                }
            }
            .onChange(of: showAllFloors) { _, _ in selection = [] }
            .sheet(isPresented: $showingFloorPicker) {
                ParkingBatchFloorView(store: store, lotID: lotID, pointIDs: selectedParkingIDs) {
                    selection = []
                    selecting = false
                    if groupID != nil && records.isEmpty { showAllFloors = true }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func recordRow(_ point: ParkingPointRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: point.isAutomotive ? "parkingsign.circle" : "figure.stand")
                .font(.title3)
                .foregroundStyle(point.isAutomotive ? Color.orange : Color.teal)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(point.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(point.displayFloor ?? String(localized: "未知"))
                    Text(point.floorStatusLabel)
                    if let spot = point.llmSpotNumber, !spot.isEmpty { Text(spot) }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            if point.id == store.currentPoint?.id {
                Text(String(localized: "最新")).font(.caption).foregroundStyle(.secondary)
            }
            if !selecting { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ParkingBatchFloorView: View {
    @ObservedObject var store: ParkingFloorStore
    let lotID: UUID
    let pointIDs: Set<UUID>
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var floor = 0
    @State private var confirming = false
    private var lot: ParkingLotRecord? { store.lots.first { $0.id == lotID } }
    private var validIDs: Set<UUID> {
        Set(lot?.points.filter { pointIDs.contains($0.id) && $0.isAutomotive }.map(\.id) ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "樓層"), selection: $floor) {
                        ForEach(-10...30, id: \.self) { floor in
                            Text(ParkingFloorStore.formatFloor(floor, coordinate: lot?.centerCoordinate)).tag(floor)
                        }
                    }.pickerStyle(.wheel)
                    LabeledContent(String(localized: "停車記錄"), value: "\(validIDs.count)")
                } footer: {
                    Text(String(localized: "只修正所選記錄，不會更改其他記錄、停車場或真實位置。"))
                }
            }
            .navigationTitle(String(localized: "修正樓層"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "儲存")) { confirming = true }.disabled(validIDs.isEmpty)
                }
            }
            .confirmationDialog(String(format: String(localized: "將 %d 筆記錄的樓層修正為 %@？"),
                validIDs.count, ParkingFloorStore.formatFloor(floor, coordinate: lot?.centerCoordinate)),
                isPresented: $confirming, titleVisibility: .visible) {
                Button(String(localized: "確認修正")) {
                    store.setManualFloors(pointIDs: validIDs, floorIndex: floor)
                    onSave()
                    dismiss()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            }
            .onAppear {
                floor = lot?.points.first { validIDs.contains($0.id) }?.effectiveFloorIndex ?? 0
            }
        }
        .presentationDetents([.medium])
    }
}
