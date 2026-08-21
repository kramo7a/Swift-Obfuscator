protocol LocalService { func send() }
struct Client: LocalService { func send() {} }
