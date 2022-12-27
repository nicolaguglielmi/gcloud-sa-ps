Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net
$VerbosePreference =  "Continue"

# configuration (adapt to your setup!)
$CertFile = "sa.p12"
$CertPassword = "notasecret"
$Project = "integral-plexus-xxxxxx"
$ServiceAccountName = "backup-to-gdrive"
$ServiceAccount = "backup-to-gdrive@integral-plexus-xxxx.iam.gserviceaccount.com"
$Scope = "https://www.googleapis.com/auth/drive"
$ExpirationSeconds = 3600

# import certificate
$Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertFile,$CertPassword,[System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
$RSACryptoServiceProvider = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$RSACryptoServiceProvider.ImportParameters($Certificate.PrivateKey.ExportParameters($true))

# create JWT Header
$JwtHeader = '{"alg":"RS256","typ":"JWT"}'
$JwtHeaderBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($JwtHeader))
$JwtHeaderBase64UrlEncoded = $JwtHeaderBase64 -replace "/","_" -replace "\+","-" -replace "=", ""

# create JWT Claim Set
$Now = (Get-Date).ToUniversalTime()
#rewrite of unix timestamp conversion
$NowUnixTimestamp = (Get-Date -Date ($Now.DateTime) -UFormat %s)
$Expiration = $Now.AddSeconds($ExpirationSeconds)
$ExpirationUnixTimestamp = (Get-Date -Date ($Expiration.DateTime) -UFormat %s)
$JwtClaimSet = @"
{"iss":"$ServiceAccount","scope":"$Scope","aud":"https://oauth2.googleapis.com/token","exp":$ExpirationUnixTimestamp,"iat":$NowUnixTimestamp}
"@
$JwtClaimSetBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($JwtClaimSet))
$JwtClaimSetBase64UrlEncoded = $JwtClaimSetBase64 -replace "/","_" -replace "\+","-" -replace "=", ""

# calculate Signature
$StringToSign = $JwtHeaderBase64UrlEncoded + "." + $JwtClaimSetBase64UrlEncoded
$SHA256 = [System.Security.Cryptography.SHA256]::Create()
$Hash = $SHA256.ComputeHash([Text.Encoding]::UTF8.GetBytes($StringToSign))
$SignatureBase64 = [Convert]::ToBase64String($RSACryptoServiceProvider.SignData([System.Text.Encoding]::UTF8.GetBytes($StringToSign),"SHA256"))
$SignatureBase64UrlEncoded = $SignatureBase64 -replace "/","_" -replace "\+","-" -replace "=", ""

# create JWT
$Jwt = $JwtHeaderBase64UrlEncoded + "." + $JwtClaimSetBase64UrlEncoded + "." + $SignatureBase64UrlEncoded

#create the body of the request
$Body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$Jwt"

#set the endpoint for the request
$uri = "https://www.googleapis.com/oauth2/v4/token"

# send JWT request for oauth access token
$AccessToken = Invoke-RestMethod -Method Post -Uri $uri -Body $Body -ContentType "application/x-www-form-urlencoded" | Select-Object -ExpandProperty access_token

# Select the file you wish to upload
$SourceFile = 'upload.txt'

# Get the source file contents and details, encode in base64
$sourceItem = Get-Item $sourceFile
$sourceBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourceItem.FullName))
$sourceMime = [System.Web.MimeMapping]::GetMimeMapping($sourceItem.FullName)

# If uploading to a Team Drive, set this to 'true'
$supportsTeamDrives = 'false'

# Set the file metadata
$uploadMetadata = @{
    originalFilename = $sourceItem.Name
    name = $sourceItem.Name
    description = $sourceItem.VersionInfo.FileDescription
    #parents = @('teamDriveid or folderId') # Include to upload to a specific folder
    #teamDriveId = ‘teamDriveId’            # Include to upload to a specific teamdrive
}

# Set the upload body
$uploadBody = @"
--boundary
Content-Type: application/json; charset=UTF-8

$($uploadMetadata | ConvertTo-Json)

--boundary
Content-Transfer-Encoding: base64
Content-Type: $sourceMime

$sourceBase64
--boundary--
"@

# Set the upload headers
$uploadHeaders = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type" = 'multipart/related; boundary=boundary'
    "Content-Length" = $uploadBody.Length
}


# Perform the upload
$response = Invoke-RestMethod -Uri "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsTeamDrives=$supportsTeamDrives" -Method Post -Headers $uploadHeaders -Body $uploadBody
