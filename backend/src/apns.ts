export type APNSAuthKey = {
    keyId: string;
    teamId: string;
    privateKey: string; // Provide in PEM format
};

async function createJwt(key: APNSAuthKey, algorithm = { name: "ECDSA", namedCurve: "P-256" }) {
    // Prepare the signing key from the provided P8 private key
    let privateKeyP8B64Decoded = Buffer.from(key.privateKey, 'base64').toString('utf8');
    const ecPrivateKey = await crypto.subtle.importKey(
        'pkcs8',
        Buffer.from(privateKeyP8B64Decoded.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\n/g, ''), 'base64'),
        algorithm,
        false,
        ['sign']
    );

    // Define JWT Header
    const header = {
        alg: 'ES256',
        kid: key.keyId
    };

    // Define JWT Payload
    const timeNow = Math.floor(Date.now() / 1000);
    const payload = {
        iss: key.teamId,
        iat: timeNow,
        exp: timeNow + 3600
    };

    const toUrlBase64 = (text: string) => Buffer.from(text).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const encodedHeader = toUrlBase64(JSON.stringify(header));
    const encodedPayload = toUrlBase64(JSON.stringify(payload));
    const signTarget = `${encodedHeader}.${encodedPayload}`;

    // Sign the Token
    const signature = await crypto.subtle.sign(
        algorithm,
        ecPrivateKey,
        Buffer.from(signTarget)
    );

    // Return the complete JWT
    return `${signTarget}.${Buffer.from(signature).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`;
}

export async function sendPushNotification(title: string, body: string, key: APNSAuthKey, deviceToken: string, bundleId: string) {
    const jwt = await createJwt(key);
    const payload = JSON.stringify({
        aps: {
            alert: {
                title: title,
                body: body
            },
            sound: "default",
            category: "DEVELOPER_RESPONSE"
        }
    });

    const response = await fetch(`https://api.development.push.apple.com/3/device/${deviceToken}`, {
        method: 'POST',
        headers: {
            'authorization': `bearer ${jwt}`,
            'apns-topic': bundleId,
            'content-type': 'application/json'
        },
        body: payload
    });

    if (!response.ok) {
        const errorData = await response.text();
        throw new Error(`Failed to send push notification: ${errorData}`);
    }

    console.log('Push notification sent successfully!');
}

