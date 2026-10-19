# Store privacy answers

Answers for the Google Play **Data safety** form and the App Store
**App Privacy** questionnaire, with the reasoning behind each, so they can be
re-checked when the app changes. They must match
[PRIVACY_POLICY.md](../PRIVACY_POLICY.md).

The basis for every answer: the app has no SDKs that send data (no
analytics, crash reporting, ads or login), chats are stored only on the
device, and the only network traffic is downloading the signed model catalog
and model files. Re-check these answers whenever a dependency is added (see
`docs/DEPENDENCIES.md`).

## Google Play: Data safety

| Question | Answer | Why |
|---|---|---|
| Does your app collect or share any of the required user data types? | **No** | Play counts data as collected only when it is transmitted off the device. Chats, settings and device facts never leave the phone. Catalog and model downloads carry no user data; the IP address seen by a server when delivering a file is not "collected" by the app under Play's definition, and the catalog server does not retain it for any purpose other than delivery and abuse prevention. |
| Is all of the user data collected by your app encrypted in transit? | Not applicable (no data collected). All network traffic is HTTPS only (cleartext disabled). | |
| Do you provide a way for users to request that their data is deleted? | Not applicable (no data collected). In app: delete conversations, delete all chats, delete all models; uninstalling deletes everything. | |
| Account creation | None | |
| Data deletion URL | Not required | No accounts |

Other Play Console declarations:

| Declaration | Answer |
|---|---|
| Ads | The app contains no ads |
| Target audience | 13+ (AI generated content); not designed for children |
| Content rating (IARC) | Answer "yes" to user generated / AI generated content that is not moderated: the model may produce any text. No user to user interaction, no sharing, no location, no purchases. |
| Government app, financial features, health | No |
| Foreground service (dataSync) | Used for user started model downloads that must continue with the screen off. Video: start a download, lock the phone, show the notification progress. |
| Permissions: `USE_BIOMETRIC` | Optional app lock |
| Permissions: `POST_NOTIFICATIONS` | Download progress notification |
| Permissions: `SET_ALARM` | Chat commands such as "set an alarm for 7" hand the alarm to the clock app. Normal permission, granted at install. |
| Package visibility (`<queries>` for launcher apps, not `QUERY_ALL_PACKAGES`) | "Open YouTube" looks up home screen apps by name at that moment; the list is not stored or transmitted. |
| Home screen widget | One button that opens a new chat with voice typing. |
| Permissions: `RECORD_AUDIO` | Voice typing in the chat box, only while the user taps the microphone. Recognition uses the phone's on-device recognizer only; audio is not stored or transmitted, so it is not "collected" data. |
| Generative AI policy | The app runs downloadable open models on device. Report path: the model licenses screen links to each model's license; offensive output can be reported through the store listing contact. |

## App Store: App Privacy

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** |
| Tracking | No |
| Privacy manifest | `ios/Runner/PrivacyInfo.xcprivacy`: no tracking, no collected data types; required reason APIs: disk space (E174.1, 85F4.1), UserDefaults (CA92.1). Plugins include their own manifests. |
| Privacy policy URL | `https://emberwit.app/privacy` (host `docs/PRIVACY_POLICY.md` there before submitting) |
| Age rating | 12+ ("Infrequent/Mild" mature themes may appear in unmoderated AI generated text); no web browsing, no user generated content sharing |
| Encryption export compliance | Uses only standard encryption (SQLCipher AES, AES-GCM, HTTPS) for data protection: exempt. Set `ITSAppUsesNonExemptEncryption` to `NO` after confirming with the publisher's legal advice. |
| Face ID usage description | "Face ID unlocks Emberwit when the app lock is on." (`Info.plist`) |
