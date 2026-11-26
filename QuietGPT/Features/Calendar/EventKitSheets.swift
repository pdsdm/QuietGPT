import EventKit
import EventKitUI
import SwiftUI

struct EventEditSheet: UIViewControllerRepresentable {
    let store: EKEventStore
    let event: EKEvent
    let done: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(done: done)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: () -> Void

        init(done: @escaping () -> Void) {
            self.done = done
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            done()
        }
    }
}

struct EventDetailSheet: UIViewControllerRepresentable {
    let event: EKEvent
    let done: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = true
        controller.allowsCalendarPreview = true
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(done: done)
    }

    final class Coordinator: NSObject, EKEventViewDelegate {
        let done: () -> Void

        init(done: @escaping () -> Void) {
            self.done = done
        }

        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            done()
        }
    }
}
