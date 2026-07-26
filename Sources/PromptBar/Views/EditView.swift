import SwiftUI

/// Edit state: a tall field prefilled with the selected variant.
/// Editing is local text editing — it never triggers regeneration.
struct EditView: View {
    @Bindable var model: PromptBarViewModel
    var editorFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Editing · \(model.selectedStyle.title)")
                        .font(Theme.font(11.5, .medium))
                }
                .foregroundStyle(Theme.label2)

                PromptTextEditor(
                    text: $model.currentPromptText,
                    placeholder: "",
                    height: 220,
                    font: Theme.font(13.5),
                    focused: editorFocused
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            HairlineDivider()

            HStack(spacing: 9) {
                FooterHint(text: "esc to stop editing")
                Spacer()
                Button("Done") { model.endEditing() }
                    .buttonStyle(.glass)
                Button("Copy & Close") { model.copySelectedAndClose() }
                    .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
    }
}
