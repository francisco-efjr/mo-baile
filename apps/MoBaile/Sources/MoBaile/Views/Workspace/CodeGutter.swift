import SwiftUI

struct CodeGutter: View {
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        VStack {
            Text("1")
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundColor(themeManager.current.syntaxGutter)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 10)
                .padding(.trailing, 4)
            
            Spacer()
        }
        .frame(width: 34)
        .background(themeManager.current.syntaxGutterBg)
    }
}
