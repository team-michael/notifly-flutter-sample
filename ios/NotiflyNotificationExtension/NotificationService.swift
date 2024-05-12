import notifly_sdk

class NotificationService: NotiflyNotificationServiceExtension {
    override init() {
        super.init()
        self.setup()
    }

    func setup() {
        self.register(projectId: "a0d696d1aba7535fad6710cddf3b1cab", username: "minyong")
    }
}
