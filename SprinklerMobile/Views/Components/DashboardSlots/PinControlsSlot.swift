import SwiftUI

struct PinControlsSlot: View {
    let pins: [PinDTO]
    let onTogglePin: (PinDTO, Int) async -> Void
    @State private var expandedPins: Set<Int> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin Controls")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            
            LazyVStack(spacing: 8) {
                ForEach(pins.filter { $0.isEnabled ?? true }, id: \.pin) { pin in
                    PinControlRow(
                        pin: pin,
                        isExpanded: expandedPins.contains(pin.pin),
                        onToggle: { duration in
                            Task {
                                await onTogglePin(pin, duration)
                            }
                        },
                        onExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedPins.contains(pin.pin) {
                                    expandedPins.remove(pin.pin)
                                } else {
                                    expandedPins.insert(pin.pin)
                                }
                            }
                        }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pin Controls")
    }
}

struct PinControlRow: View {
    let pin: PinDTO
    let isExpanded: Bool
    let onToggle: (Int) async -> Void
    let onExpand: () -> Void
    
    @State private var selectedDuration: Int = 10
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var isToastError = false
    
    private let durationPresets = [1, 5, 10, 15, 30, 60]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if pin.isActive ?? false {
                        Text("Running")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Zone \(pin.pin)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Toggle("", isOn: .constant(pin.isActive ?? false))
                        .labelsHidden()
                        .disabled(true)
                        .accessibilityLabel("Pin \(pin.pin) status")
                        .accessibilityValue((pin.isActive ?? false) ? "On" : "Off")
                    
                    Button(action: onExpand) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle((pin.isActive ?? false) ? .red : .blue)
                    }
                    .accessibilityLabel((pin.isActive ?? false) ? "Stop \(pin.displayName)" : "Start \(pin.displayName)")
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                onExpand()
            }
            
            if isExpanded {
                durationSelector
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .toast(isPresented: $showingToast, message: toastMessage, isError: isToastError)
    }
    
    private var durationSelector: some View {
        VStack(spacing: 12) {
            Text("Run Duration")
                .font(.subheadline)
                .fontWeight(.medium)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(durationPresets, id: \.self) { duration in
                    Button("\(duration) min") {
                        selectedDuration = duration
                        Task {
                            await performToggle(duration: duration)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Run for \(duration) minutes")
                }
            }
            
            if pin.isActive ?? false {
                Button("Stop") {
                    Task {
                        await performToggle(duration: 0)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .accessibilityLabel("Stop \(pin.displayName)")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func performToggle(duration: Int) async {
        do {
            await onToggle(duration)
            let action = duration == 0 ? "stopped" : "started for \(duration) minutes"
            showToast(message: "\(pin.displayName) \(action)", isError: false)
        } catch {
            showToast(message: "Failed to toggle \(pin.displayName)", isError: true)
        }
    }
    
    private func showToast(message: String, isError: Bool) {
        toastMessage = message
        isToastError = isError
        showingToast = true
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, isError: Bool = false) -> some View {
        self.overlay(
            Group {
                if isPresented.wrappedValue {
                    VStack {
                        Spacer()
                        
                        HStack {
                            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(isError ? .red : .green)
                            
                            Text(message)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                isPresented.wrappedValue = false
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut, value: isPresented.wrappedValue)
        )
    }
}
