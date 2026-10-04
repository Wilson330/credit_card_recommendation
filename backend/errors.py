"""API 錯誤:帶 HTTP 狀態碼與給使用者看的訊息。"""


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message
