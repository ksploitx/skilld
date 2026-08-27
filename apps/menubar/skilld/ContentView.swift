import SwiftUI

struct Skill: Identifiable {
    let id = UUID()
    let name: String
    let description: String
}

struct ContentView: View {
    let fakeSkills = [
        Skill(name: "Python Expert", description: "Advanced python coding skill"),
        Skill(name: "React Developer", description: "Frontend react components"),
        Skill(name: "SwiftUI Master", description: "macOS UI generation")
    ]

    var body: some View {
        VStack {
            Text("skilld library")
                .font(.headline)
                .padding()

            List(fakeSkills) { skill in
                VStack(alignment: .leading) {
                    Text(skill.name).font(.subheadline).bold()
                    Text(skill.description).font(.caption).foregroundColor(.secondary)

                    Button("Install") {
                        // TODO: file operation to install to ~/.claude/skills/ will go here
                        print("Installing \(skill.name)")
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 300, height: 400)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
