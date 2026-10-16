//
//  HomeView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI


struct HomeView: View {
    @Bindable var applicationStore: ApplicationStore
    @State private var isBrowsing = false
    @State private var selectedWorkout = Workout.Kind.badminton

    var body: some View {

        NavigationStack {
            VStack(spacing: 12) {
                AppHeaderView()
                    .blur(radius: isBrowsing ? 4 : 0)
                    .opacity(isBrowsing ? 0.3 : 1)

                Spacer()

                WorkoutSelectionView(selection: $selectedWorkout, isBrowsing: $isBrowsing) {
                    Task { await applicationStore.start(selectedWorkout) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .blur(radius: isBrowsing ? 4 : 0)
                    .opacity(isBrowsing ? 0.3 : 1)
                    .allowsHitTesting(!isBrowsing)
                    .disabled(isBrowsing)
                }
            }
        }
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: Workout.Kind.key).flatMap(Workout.Kind.init(rawValue:)) {
                selectedWorkout = saved
            }
        }
    }
}

#Preview {
    HomeView(applicationStore: ApplicationStore())
}


private struct WorkoutSelectionView: View {
    @Binding var selection: Workout.Kind
    @Binding var isBrowsing: Bool
    var onStart: () -> Void = {}

    @State private var isScrolling = false

    private let list = Workout.Kind.allCases
    private let rowHeight: CGFloat = 56

    /// The list is open but nothing is moving, which is when the collapse countdown runs
    private var isIdleWhileBrowsing: Bool {
        isBrowsing && !isScrolling
    }

    var body: some View {
        // The scroll view is exactly one row tall, so the snapped row always sits in the
        // green chrome. Clipping is off so the faded neighbors still show above and below.
        ScrollView {
            VStack(spacing: 8) {
                ForEach(list, id: \.self) { workout in
                    row(for: workout)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.green.gradient)
                .scaleEffect(isBrowsing ? 1.08 : 1)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        // The centered row is the selection, so landing on a workout selects it
        .scrollPosition(id: Binding($selection), anchor: .center)
        .padding(.horizontal)
        // Only while browsing, so restoring the saved workout on appear doesn't tick
        .sensoryFeedback(.selection, trigger: selection) { _, _ in isBrowsing }
        .onScrollPhaseChange { _, newPhase in
            isScrolling = newPhase.isScrolling
            if newPhase.isScrolling {
                withAnimation(.snappy) { isBrowsing = true }
            }
        }
        // Restarts whenever scrolling starts or stops, so the list closes shortly after it settles
        .task(id: isIdleWhileBrowsing) {
            guard isIdleWhileBrowsing else { return }
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { isBrowsing = false }
        }
    }

    private func row(for workout: Workout.Kind) -> some View {
        let isSelected = workout == selection

        return Button {
            if isBrowsing {
                withAnimation { selection = workout } // tapping a row selects it and scrolls it into place
            } else {
                onStart()                             // tapping "Start Workout" starts the selected one
            }
        } label: {
            Label(isBrowsing ? workout.name : "Start Workout",
                  systemImage: workout.symbol)
                .contentTransition(.symbolEffect(.replace))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected && isBrowsing ? 1.08 : 1)
        .opacity(isSelected ? 1 : (isBrowsing ? 0.4 : 0))
        .animation(.snappy, value: isSelected)
    }
}

#Preview("Workout Selection") {
    @Previewable @State var selection = Workout.Kind.badminton
    @Previewable @State var isBrowsing = false
    WorkoutSelectionView(selection: $selection, isBrowsing: $isBrowsing)
}
