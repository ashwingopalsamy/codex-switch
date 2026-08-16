import AppKit
import CodexSwitchCore
import SwiftUI

struct AddProfileCardView: View {
    let model: AppModel
    @State private var profileName: String = ""

    init(model: AppModel) {
        self.model = model
    }

    private func createProfile() {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.createProfile(named: trimmed)
        profileName = ""
    }

    private var isSubmitDisabled: Bool {
        profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)

                TextField("New profile (e.g. Work, Research)", text: $profileName)
                    .textFieldStyle(.plain)
                    .font(UITheme.Typography.input)
                    .onSubmit {
                        createProfile()
                    }

                if !profileName.isEmpty {
                    Button {
                        profileName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .unfocusedControl()
                }

                Button {
                    createProfile()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(isSubmitDisabled ? Color.primary.opacity(0.3) : Color(nsColor: .windowBackgroundColor))
                        .background(isSubmitDisabled ? Color.primary.opacity(0.06) : Color.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .unfocusedControl()
                .disabled(isSubmitDisabled)
                .instantTooltip("Create new profile")
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }

            Text("Managed profiles are created with isolated roots below Application Support.")
                .font(UITheme.Typography.micro)
                .foregroundStyle(.tertiary)
                .padding(.leading, 6)
        }
        .padding(.horizontal, UITheme.Spacing.cardPaddingHorizontal)
        .padding(.vertical, 10)
        .cardSurface(radius: UITheme.Radius.card)
    }
}
