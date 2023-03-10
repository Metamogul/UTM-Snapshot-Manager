# UTM Snapshot Manager

This is a companion app for the popular MacOS virtual machine host [UTM](https://github.com/utmapp/UTM) to manage snapshots for existing virtual machines. UTM itself doesn't give access to that functionality so far; however the QEMU hypervisor, on which UTM is based, offers [snapshot management](https://kashyapc.fedorapeople.org/virt/lc-2012/snapshots-handout.html). This project is more intended as proof-of-concept for that functionality and less as a releasable product – especially it doesn't come with a precompiled release binary (since I don't have a paid Apple Developer subscription to create an app package signed for distribution). However it should be perfectly possible to just download and compile it out of the box.

![UTM Snapshot Manager - Screenshot of the main window with navigation pane on the left and details view with VMs on the right](https://github.com/Metamogul/UTM-Snapshot-Manager/blob/main/Screenshot.png)

## Building ##

Clone the repository ( `git clone git@github.com:Metamogul/UTM-Snapshot-Manager.git` ), open the included project file in a recent XCode version (14.2. or newer) and build. There are no further source dependencies.

### Dependencies ###

For it's functionality the app depends on `qemu-img` – it's basically a nice UI frontend for it. The app expects to find it at `/opt/homebrew/bin/qemu-img`. This dependency is not included. It can be installed as part of the brew qemu package via `brew install qemu`.

## Usage ##

Use the navigation pane on the right to manage groups of VMs. A group can also just contain one virtual machine. With a group selected, virtual machines can be added via the ➕ icon in the navigation area. Every virtual machine in a group will display a list of it's snapshots or a placeholder if there are none. Use the ➕, ➖ and 🔄 icons in the central toolbar area to create, delete or restore a snapshot for every VM in the group. Open a context menu in an empty space at the bottom of a snapshot list to add a snapshot to just that single virtual machine. Select a snapshot in a list and open a context menu to restore or delete just that particular snapshot.

## Known issues ##

During development and testing, I've discovered a number of minor issues with the UI which I didn't take the time to fix so far.

- When deleting the VM group directly over the creation button, the creation button will be highlighted until clicked again.
- Selecting a row in a snapshot table sometimes takes clicking on it twice or more, same goes for opening the context menu on it.
- When deleting a snapshot, occasionally a bunch of `=== AttributeGraph: cycle detected through attribute 787512 ===` warnings show up in the debug log.

## Contributing ##

Feel free to contribute by creating a fork and issuing a pull request. When issuing a pull request, it would be nice if you could relate it to an open ticket so there's documentation later on.

If you're part of the UTM development team and want to incorporate such functionality into UTM, let me know. I'd be glad to help.

## License ##

This project is distributed under the permissive [Apache 2.0 license](https://github.com/Metamogul/UTM-Snapshot-Manager/blob/main/LICENSE) as included. It doesn't use any other source components, packages or libraries under different licenses (apart from Apple's own system frameworks).

The app icon is taken from the orignal UTM project and included with the source under an Apache 2.0 license as well. If you're part of that project and feel that this is not appropriate, please contact me so I can replace it.
