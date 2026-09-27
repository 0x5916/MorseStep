package common

import "errors"

var ErrExpiredToken = errors.New("expired")
var ErrInvalidToken = errors.New("invalid")

const (
	ErrorCodeInvalidRequestBody      = "INVALID_REQUEST_BODY"
	ErrorCodeInternalServerError     = "INTERNAL_SERVER_ERROR"
	ErrorCodeDatabaseFailure         = "DATABASE_FAILURE"
	ErrorCodeInvalidCredentials      = "INVALID_CREDENTIALS"
	ErrorCodeConflict                = "CONFLICT"
	ErrorCodeInvalidToken            = "INVALID_TOKEN"
	ErrorCodeExpiredToken            = "EXPIRED_TOKEN"
	ErrorCodeAuthHeaderRequired      = "AUTH_HEADER_REQUIRED"
	ErrorCodeInvalidAuthHeaderFormat = "INVALID_AUTH_HEADER_FORMAT"
	ErrorCodeUserNotFound            = "USER_NOT_FOUND"
	ErrorCodeSettingsFetchFailed     = "SETTINGS_FETCH_FAILED"
	ErrorCodeSettingsUpdateFailed    = "SETTINGS_UPDATE_FAILED"
	ErrorCodeProgressQueryFailed     = "PROGRESS_QUERY_FAILED"
	ErrorCodeProgressCreateFailed    = "PROGRESS_CREATE_FAILED"
	ErrorCodePasswordHashFailed      = "PASSWORD_HASH_FAILED"
	ErrorCodeTokenIssueFailed        = "TOKEN_ISSUE_FAILED"
	ErrorCodeEmailAlreadyInUse       = "EMAIL_ALREADY_IN_USE"
	ErrorCodeEmailVerifiedByAnother  = "EMAIL_VERIFIED_BY_ANOTHER_ACCOUNT"
	ErrorCodeUsernameAlreadyInUse    = "USERNAME_ALREADY_IN_USE"
	ErrorCodeEmailUnchanged          = "EMAIL_UNCHANGED"
	ErrorCodeEmailAlreadyVerified    = "EMAIL_ALREADY_VERIFIED"
	ErrorCodeVerificationCodeInvalid = "VERIFICATION_CODE_INVALID"
	ErrorCodeVerificationCodeExpired = "VERIFICATION_CODE_EXPIRED"
	ErrorCodeVerificationSendFailed  = "VERIFICATION_SEND_FAILED"
	ErrorCodeVerificationRateLimited = "VERIFICATION_RATE_LIMITED"
	ErrorCodeCallSignAlreadyInUse    = "CALL_SIGN_ALREADY_IN_USE"
	ErrorCodeEmailNotVerified        = "EMAIL_NOT_VERIFIED"
	ErrorCodeThreadNotFound          = "THREAD_NOT_FOUND"
	ErrorCodeReplyNotFound           = "REPLY_NOT_FOUND"
	ErrorCodeNotAuthor               = "NOT_AUTHOR"
	ErrorCodeInvalidQueryParameter   = "INVALID_QUERY_PARAMETER"
	ErrorCodeForumQueryFailed        = "FORUM_QUERY_FAILED"
	ErrorCodeForumCreateFailed       = "FORUM_CREATE_FAILED"
	ErrorCodeForumDeleteFailed       = "FORUM_DELETE_FAILED"
	ErrorCodeForumRateLimited        = "FORUM_RATE_LIMITED"
)

func NewErrorResponse(code string, message string) ErrorResponse {
	return ErrorResponse{Code: code, Error: message}
}
