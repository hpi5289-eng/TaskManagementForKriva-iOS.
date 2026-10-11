# Task Management for Kriva – iPhone ऐप

- iPhone के लिए: **iOS 13 या नया** (iPhone 6s और उसके बाद के सभी iPhone)। होम-स्क्रीन विजेट के लिए iOS 14 या नया चाहिए।
- Android ऐप जैसा ही: Login, Home, Add work (Contacts से नंबर, ग्राहक नाम के सुझाव), View work, Work details (Done / Approve / Assign / Note / Edit / Cancel), Payment QR (WhatsApp API, Share, UPI ऐप), My notes (रिमाइंडर के साथ, सिर्फ इस फोन में), Admin Backup (हाथ से और हर 24 घंटे में अपने-आप), Owner/Reseller पैनल (Companies, Payments, Tickets), और 4 विजेट।
- **Call log नहीं है:** Apple किसी भी ऐप को कॉल लिस्ट पढ़ने नहीं देता। इसलिए Add work में सिर्फ "👤 Contacts" बटन है।
- विजेट में ✓ दबाने पर ऐप में "Mark done" खुलता है, क्योंकि iPhone विजेट में टाइप नहीं हो सकता।
- बैकअप: Files ऐप → On My iPhone → Kriva Tasks → Kriva Management Backup। Restore सिर्फ वेबसाइट से।

## .ipa फाइल कैसे बनती है
GitHub पर `.github/workflows/ios.yml` Mac सर्वर पर ऐप बनाता है। Actions → iOS build → Artifacts में `TaskManagementForKriva-unsigned.ipa` मिलती है।

## iPhone में कैसे डालें
1. **अपने टेस्ट के लिए (मुफ़्त):** Windows/Mac पर Sideloadly इंस्टॉल करें, iPhone USB से जोड़ें, .ipa डालें और अपनी Apple ID से साइन करें। हर 7 दिन में दोबारा करना पड़ता है।
2. **कस्टमर को देने के लिए:** Apple Developer अकाउंट ($99/साल) बनाएँ। फिर App Group `group.com.kriva.taskmanagement` और Bundle ID `com.kriva.taskmanagement` (विजेट `com.kriva.taskmanagement.widget`) रजिस्टर करके Xcode या GitHub से साइन करके TestFlight / App Store पर डालें।
