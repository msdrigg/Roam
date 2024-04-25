import { APNSAuthKey, sendPushNotification } from "./apns";
import DiscordClient, { DiscordFile, DiscordMessage } from "./discord";

export interface Env {
	ROAM_KV: KVNamespace;

	// Secrets
	DISCORD_TOKEN: string;
	DISCORD_HELP_CHANNEL: string;
	DISCORD_BOT_ID: string;
	DISCORD_GUILD_ID: string;

	APNS_KEY_ID: string;
	APNS_TEAM_ID: string;
	APNS_PRIVATE_KEY: string;

	API_KEY: string;

	// Vars
	ROAM_BUNDLE_ID: string;
}

type MessageRequest = {
	title: string;
	content: string;
	userId: string;
	apnsToken: string | null;
	installationInfo: InstallationInfo;
}

type InstallationInfo = {
	userId: string;
	buildVersion: string | null;
	osPlatform: string | null;
	osVersion: string | null;
}

async function sendDeviceInfoIfNotSent(env: Env, userId: string, threadId: string, installationInfo: InstallationInfo | undefined, discordClient: DiscordClient) {
	let alreadySentDeviceInfo = await env.ROAM_KV.get(`deviceInfoSent:${userId}`);
	console.log(`Maybe sending device info: alreadySent=${alreadySentDeviceInfo} blank=${!installationInfo}`);

	if (!alreadySentDeviceInfo && installationInfo) {
		let { userId, buildVersion, osPlatform, osVersion } = installationInfo;
		await discordClient.sendMessage(threadId, `:ninja:\n\n**Device info**:\n- User ID: ${userId}\n- Build version: ${buildVersion}\n- OS platform: ${osPlatform}\n- OS version: ${osVersion}`);
		await env.ROAM_KV.put(`deviceInfoSent:${userId}`, "true");
	}
}

async function sendMessage(message: {
	title?: string,
	content?: string,
	attachment?: DiscordFile,
},
	userInfo: {
		apnsToken: string | null,
		userId: string,
		installationInfo?: InstallationInfo,
	},
	env: Env, discordClient: DiscordClient): Promise<void> {
	const { title, content, attachment: attachment } = message;
	const { apnsToken, userId, installationInfo } = userInfo;

	console.log("Handling new message request", title, content, apnsToken, userId);

	let threadId = await env.ROAM_KV.get(`threadId:${userId}`);
	console.log(`Existing thread ID: ${threadId}`)

	if (threadId) {
		if (content) {
			await discordClient.sendMessage(threadId, content)
		}
	} else {
		threadId = await discordClient.createThread(title || `New message from ${userId}`, content || "");
		await env.ROAM_KV.put(`threadId:${userId}`, threadId);
	}

	if (attachment) {
		await discordClient.sendAttachment(threadId, attachment)
	}


	await sendDeviceInfoIfNotSent(env, userId, threadId, installationInfo, discordClient);

	if (apnsToken) {
		await env.ROAM_KV.put(`apnsToken:${threadId}`, apnsToken);
		await env.ROAM_KV.put(`apnsToken:${userId}`, apnsToken);
	}
}


export default {
	async fetch(request, env, _ctx): Promise<Response> {
		let pathSegments = new URL(request.url).pathname.split("/").filter(Boolean);
		let apiKeyHeader = request.headers.get("x-api-key");
		if (apiKeyHeader !== env.API_KEY) {
			return new Response("Unauthorized", { status: 401 });
		}

		let discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);

		if (pathSegments.length === 0) {
			return new Response("Hello, world!", { status: 200 });
		}

		if (pathSegments[0] === "messages") {
			let userId = pathSegments[1];
			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}
			let threadId = await env.ROAM_KV.get(`threadId:${userId}`);

			let queryParams = new URL(request.url).searchParams;
			let after = queryParams.get("after") || null;

			if (!threadId) {
				return new Response("Not found", { status: 404 });
			}

			let messages = (await discordClient.getMessagesInThread(threadId, after))
				.filter((message) => !isHidden(message));

			return new Response(JSON.stringify(messages), { status: 200 });
		}

		if (pathSegments[0] === "new-message") {
			let messageRequest = await request.json() as MessageRequest;
			let {
				title,
				content,
				apnsToken,
				userId,
				installationInfo,
			} = messageRequest;

			if (!userId) {
				return new Response("Bad request", { status: 400 });
			}

			await sendMessage({ title, content }, { apnsToken, userId, installationInfo }, env, discordClient);


			return new Response("OK", { status: 200 });
		}

		if (pathSegments[0] === "upload-diagnostics") {
			let diagnosticKey = pathSegments[1];

			if (!diagnosticKey) {
				return new Response("Bad request", { status: 400 });
			}
			// User ids are of the form "xxx-xxx-xxx"
			let userId = diagnosticKey.slice(0, 11);

			let data = await request.arrayBuffer();

			await sendMessage({
				attachment: {
					name: "diagnostics.json",
					data,
					contentType: "application/json"
				}
			}, { apnsToken: null, userId }, env, discordClient);


			return new Response("OK", { status: 200 });
		}

		return new Response("Not found", { status: 404 });
	},

	async scheduled(_event, env, _ctx) {
		console.log("Handling scheduled event")
		let discordClient = new DiscordClient(env.DISCORD_TOKEN, env.DISCORD_HELP_CHANNEL, env.DISCORD_GUILD_ID);

		let latestMessageId = await env.ROAM_KV.get("latestMessageId");

		let threads = await discordClient.getActiveThreadsUpdatedSince(latestMessageId);

		let latestOverallMessageId = Math.max(latestMessageId ? parseInt(latestMessageId) : 0,
			...threads.map(thread => parseInt(thread.lastMessageId))
		);

		if (latestOverallMessageId > 0 && (!latestMessageId || latestOverallMessageId > parseInt(latestMessageId))) {
			console.log(`Found new messages since ${latestMessageId}`);

			await env.ROAM_KV.put("latestMessageId", latestOverallMessageId.toString());
		}

		let apnsKey: APNSAuthKey = {
			keyId: env.APNS_KEY_ID,
			teamId: env.APNS_TEAM_ID,
			privateKey: env.APNS_PRIVATE_KEY,
		}

		for (let thread of threads) {
			let apnsToken = await env.ROAM_KV.get(`apnsToken:${thread.id}`);
			if (!apnsToken) {
				console.log(`No APNS token found for thread ${thread.id}`);
				continue;
			} else {
				console.log(`APNS token ${apnsToken} found for thread ${thread.id}`);
			}

			let messages = (await discordClient.getMessagesInThread(thread.id, latestMessageId))
				.filter((message) => message.content && message.type in [0, 19, 20, 21] && !message.content.startsWith("!HiddenMessage"));

			for (let message of messages) {
				if (message.author.id === env.DISCORD_BOT_ID) {
					console.log("Skipping message from bot");
					// Don't notify on messages from the bot
					continue;
				}
				try {
					console.log(`Sending push notification for message: ${message.content} to ${apnsToken} with bundle ID ${env.ROAM_BUNDLE_ID}`)
					await sendPushNotification("Message from roam", message.content, apnsKey, apnsToken, env.ROAM_BUNDLE_ID);
				} catch (e) {
					console.error(`Error sending push notification: ${e}`);
				}
			}
		}
	},
} satisfies ExportedHandler<Env>;

const allowedMessages = new Set([0, 19, 20, 21]);

function isHidden(message: DiscordMessage): boolean {
	return !message.content || message.content.startsWith("!HiddenMessage") || message.content.startsWith(":ninja:") || !allowedMessages.has(message.type)
}

