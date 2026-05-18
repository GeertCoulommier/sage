@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseShouldProcessForStateChangingFunctions'
        # Test files must use ConvertTo-SecureString with plain text to create
        # mock PSCredential objects — there is no secure alternative in Pester mocks.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
