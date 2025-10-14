import asyncio
import os
from dotenv import load_dotenv

from agent_framework.azure import AzureOpenAIChatClient
from azure.identity import AzureCliCredential

load_dotenv()

azure_ai_endpoint = os.getenv("AZURE_AI_PROJECT_ENDPOINT")

agent = AzureOpenAIChatClient(credential=AzureCliCredential()).create_agent(
    instructions="You are good at telling jokes.",
    endpoint=azure_ai_endpoint,
    name="Joker"
)
async def main():
    result = await agent.run("Tell me a joke about a pirate.")
    print(result.text)

asyncio.run(main())