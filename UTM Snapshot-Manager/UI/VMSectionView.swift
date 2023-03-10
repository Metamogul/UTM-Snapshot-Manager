//
//  VMImageView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 09.03.23.
//

import SwiftUI

struct VMSectionView: View {
    @Binding var vmGroup: VMGroup
    @Binding var vm: VM
    
    static let bottomPadding: CGFloat = 10
    static let insetNormal: CGFloat = 15
    static let insetDeep: CGFloat = 18
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                if !FileManager.isValidUTMPackageUrl(vm.url) {
                    Text(LocalizedStringKey("This VM wasn't found. Has it been moved, removed or renamed?"))
                        .padding(.leading, Self.insetNormal)
                        .padding(.bottom, Self.bottomPadding)
                }
                if FileManager.isValidUTMPackageUrl(vm.url) && vm.images.count == 0 {
                    Text(LocalizedStringKey("This VM does not contain any images."))
                        .padding(.leading, Self.insetNormal)
                        .padding(.bottom, Self.bottomPadding)
                }
                ForEach(vm.images) { image in
                    VMImageView(vm: vm, image: image)
                }
                if vmGroup.vms.last != vm {
                    Divider()
                        .padding(.leading, Self.insetNormal)
                        .padding(.bottom, Self.bottomPadding)
                }
            }
        } header: {
            HStack {
                Button(action: removeVM(vm)) {
                    Label(LocalizedStringKey("Remove VM"), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .padding(6)
                .buttonStyle(RemoveButtonStyle())
                Text(vm.url.lastPathComponent)
                    .font(Font.system(size: 13, weight: Font.Weight.medium))
                    .foregroundColor(Color.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            }
        }
    }
    
    private func removeVM(_ vm: VM) -> () -> () {
        return {
            vmGroup.vms.removeAll { $0 == vm }
        }
    }
    
    private struct RemoveButtonStyle: ButtonStyle {
        func makeBody(configuration: Self.Configuration) -> some View {
            configuration.label
                .padding([.trailing, .leading], 9)
                .padding([.top, .bottom], 5)
                .foregroundColor(configuration.isPressed ? Color.white : Color.pink)
                .background(configuration.isPressed ? Color.pink : Color.pink.opacity(0.2))
                .cornerRadius(6.0)
                .clipShape(ContainerRelativeShape())
                .font(Font.system(size: 11, weight: Font.Weight.regular))
                .fontWeight(Font.Weight.regular)
        }
    }
}

struct VMSectionViewPreviewWrapper<VMGroup, VM, Content: View>: View {
    @State var vmGroup: VMGroup
    @State var vm: VM
    
    var content: (Binding<VMGroup>, Binding<VM>) -> Content

    var body: some View {
        content($vmGroup, $vm)
    }

    init(vmGroup: VMGroup, vm: VM, content: @escaping (Binding<VMGroup>, Binding<VM>) -> Content) {
        self._vmGroup = State(wrappedValue: vmGroup)
        self._vm = State(wrappedValue: vm)
        self.content = content
    }
}


struct VMSectionView_Previews: PreviewProvider {
    static var previews: some View {
        if let vmGroup = UserSettings().vmGroups.first,
           let vm = vmGroup.vms.first {
            VMSectionViewPreviewWrapper(vmGroup: vmGroup, vm: vm) { VMSectionView(vmGroup: $0, vm: $1) }
        }
    }
}
