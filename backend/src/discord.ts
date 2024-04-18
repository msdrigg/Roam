type Message = {
    id: string;
    content: string;
    author: {
        id: string;
        username: string;
        discriminator: string;
    }
    type: number;
}

type ApiError = {
    code: number;
    message: string;
}

type Thread = {
    id: string;
    name: string;
    lastMessageId: string;
}

class DiscordClient {
    private baseUrl: string = 'https://discord.com/api/v10';

    private botToken: string;
    private channelId: string;
    private guildId: string;

    constructor(botToken: string, channelId: string, guildId: string) {
        this.botToken = botToken;
        this.channelId = channelId;
        this.guildId = guildId;
    }

    async getMessagesInThread(threadId: string, lastMessageId: string | null = null, limit: number = 100): Promise<Message[]> {
        const url = new URL(`${this.baseUrl}/channels/${threadId}/messages`);
        url.searchParams.append('limit', limit.toString());
        if (lastMessageId) {
            url.searchParams.append('after', lastMessageId);
        }
        console.log(`Fetching messages in thread: ${url.toString()}`);

        try {
            const response = await fetch(url.toString(), {
                method: 'GET',
                headers: {
                    'Authorization': `Bot ${this.botToken}`
                }
            });

            if (!response.ok) {
                const errorData = await response.json() as ApiError;
                throw new Error(`Failed to fetch messages: ${errorData.message}`);
            }

            const messages = await response.json() as Message[];
            return messages;
        } catch (error) {
            console.error(`Error fetching messages in thread: ${error}`);
            throw error;
        }
    }

    async sendMessage(threadId: string, content: string): Promise<string> {
        const url = `${this.baseUrl}/channels/${threadId}/messages`;
        const body = {
            content: content
        };

        try {
            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Authorization': `Bot ${this.botToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(body)
            });

            if (!response.ok) {
                const errorData = await response.json() as ApiError;
                throw new Error(`Failed to send message: ${errorData.message}`);
            }

            const responseData = await response.json() as { id: string };
            return responseData.id;  // Return the ID of the newly created message
        } catch (error) {
            console.error(`Error sending message: ${error}`);
            throw error;
        }
    }



    async getActiveThreadsUpdatedSince(latestMessageId: string | null): Promise<Thread[]> {
        const url = `${this.baseUrl}/guilds/${this.guildId}/threads/active`;
        try {
            const response = await fetch(url, {
                method: 'GET',
                headers: {
                    'Authorization': `Bot ${this.botToken}`
                }
            });

            if (!response.ok) {
                const errorData = await response.json() as ApiError;
                throw new Error(`Failed to fetch active threads: ${errorData.message} (${errorData.code})`);
            }

            const data = await response.json() as {
                threads: any[];
            };
            const threads: Thread[] = data.threads
                .filter((thread: any) => thread.parent_id === this.channelId && (!latestMessageId || parseInt(thread.last_message_id) > parseInt(latestMessageId)))
                .map((thread: any) => ({
                    id: thread.id,
                    name: thread.name,
                    lastMessageId: thread.last_message_id
                }));

            return threads;
        } catch (error) {
            console.error(`Error fetching active threads: ${error}`);
            throw error;
        }
    }


    async createThread(title: string, message: string, autoArchiveDuration: number = 10080): Promise<string> {
        const url = `${this.baseUrl}/channels/${this.channelId}/threads`;
        const body = {
            name: title,
            auto_archive_duration: autoArchiveDuration,
            message: {
                content: message
            }
        };

        try {
            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Authorization': `Bot ${this.botToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(body)
            });

            if (!response.ok) {
                const errorData = await response.json() as ApiError;
                throw new Error(`Failed to create thread: ${errorData.message} (${errorData.code})`);
            } else {
                const data = await response.json() as {
                    id: string;
                };
                console.log(`Thread ${data.id} created successfully!`);
                return data.id;
            }

        } catch (error) {
            console.error(`Error creating thread: ${error}`);
            throw error;
        }
    }
}

export default DiscordClient;
