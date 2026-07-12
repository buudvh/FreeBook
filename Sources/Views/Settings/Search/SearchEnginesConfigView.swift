import SwiftUI

struct SearchEnginesConfigView: View {
    @State private var engines: [SearchEngine] = []
    @State private var showingAddEditSheet = false
    @State private var editingEngine: SearchEngine? = nil
    
    @State private var inputName = ""
    @State private var inputTemplate = ""
    
    var body: some View {
        List {
            Section(footer: Text("Sử dụng ký tự %s trong mẫu URL để đại diện cho từ chữ Hán được bôi đen.")) {
                ForEach(engines) { engine in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(engine.name)
                            .font(.headline)
                        Text(engine.urlTemplate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingEngine = engine
                        inputName = engine.name
                        inputTemplate = engine.urlTemplate
                        showingAddEditSheet = true
                    }
                }
                .onDelete(perform: deleteEngine)
            }
            
            Section {
                Button(action: {
                    editingEngine = nil
                    inputName = ""
                    inputTemplate = ""
                    showingAddEditSheet = true
                }) {
                    Label("Thêm công cụ mới", systemImage: "plus")
                }
                
                Button(action: restoreDefaults) {
                    Label("Khôi phục mặc định", systemImage: "arrow.counterclockwise")
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Công cụ tra cứu nhanh")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadEngines)
        .sheet(isPresented: $showingAddEditSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Thông tin công cụ")) {
                        TextField("Tên công cụ (ví dụ: Google)", text: $inputName)
                        TextField("Mẫu URL chứa %s", text: $inputTemplate)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .navigationTitle(editingEngine == nil ? "Thêm công cụ" : "Sửa công cụ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Hủy") {
                            showingAddEditSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            saveEngine()
                            showingAddEditSheet = false
                        }
                        .disabled(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  inputTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  !inputTemplate.contains("%s"))
                    }
                }
            }
            .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
            .presentationDetents([.height(260)])
        }
    }
    
    private func loadEngines() {
        engines = SearchEngine.loadEngines()
    }
    
    private func deleteEngine(at offsets: IndexSet) {
        engines.remove(atOffsets: offsets)
        SearchEngine.saveEngines(engines)
    }
    
    private func restoreDefaults() {
        engines = SearchEngine.defaults
        SearchEngine.saveEngines(engines)
    }
    
    private func saveEngine() {
        let name = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = inputTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let editing = editingEngine {
            if let index = engines.firstIndex(where: { $0.id == editing.id }) {
                engines[index].name = name
                engines[index].urlTemplate = template
            }
        } else {
            let newEngine = SearchEngine(name: name, urlTemplate: template)
            engines.append(newEngine)
        }
        SearchEngine.saveEngines(engines)
    }
}
