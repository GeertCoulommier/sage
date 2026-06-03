@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        # stopped checking unused variables and parameters because of positives in ./Sage/Private/Bencmarks
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSReviewUnusedParameter'
    )

    Rules        = @{
        PSAvoidUsingPositionalParameters = @{
            CommandAllowList = @('Join-Path')
            Enable           = $true
        }
    }
}