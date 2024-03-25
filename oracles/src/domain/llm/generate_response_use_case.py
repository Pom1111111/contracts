import backoff
from typing import List
from typing import Optional

from groq import AsyncGroq
from openai import AsyncOpenAI
from openai import RateLimitError
from openai import APIError
from openai.types.chat import ChatCompletion
from groq.types.chat import ChatCompletion as GroqChatCompletion

from src.entities import Chat
from src.domain.llm.entities import LLMResult

import settings
from src.entities import PromptType


@backoff.on_exception(backoff.expo, RateLimitError)
async def _generate(model: str, messages: List[dict]) -> Optional[str]:
    client = AsyncOpenAI(
        api_key=settings.OPEN_AI_API_KEY,
    )
    chat_completion: ChatCompletion = await client.chat.completions.create(
        messages=messages,
        model=model,
    )
    return chat_completion.choices[0].message.content


@backoff.on_exception(backoff.expo, RateLimitError)
async def _generate_openai_with_params(chat: Chat) -> Optional[ChatCompletion]:
    client = AsyncOpenAI(
        api_key=settings.OPEN_AI_API_KEY,
    )
    chat_completion: ChatCompletion = await client.chat.completions.create(
        messages=chat.messages,
        model=chat.config.model,
        frequency_penalty=chat.config.frequency_penalty,
        logit_bias=chat.config.logit_bias,
        max_tokens=chat.config.max_tokens,
        presence_penalty=chat.config.presence_penalty,
        response_format=chat.config.response_format,
        seed=chat.config.seed,
        stop=chat.config.stop,
        temperature=chat.config.temperature,
        tools=chat.config.tools,
        tool_choice=chat.config.tool_choice,
        user=chat.config.user,
    )
    assert chat_completion.choices[0].message.content or chat_completion.choices[0].message.tool_calls
    return chat_completion


@backoff.on_exception(backoff.expo, RateLimitError)
async def _generate_groq_with_params(chat: Chat) -> Optional[GroqChatCompletion]:
    client = AsyncGroq(
        api_key=settings.GROQ_API_KEY,
    )
    chat_completion: ChatCompletion = await client.chat.completions.create(
        messages=chat.messages,
        model=chat.config.model,
        frequency_penalty=chat.config.frequency_penalty,
        logit_bias=chat.config.logit_bias,
        max_tokens=chat.config.max_tokens,
        presence_penalty=chat.config.presence_penalty,
        response_format=chat.config.response_format,
        seed=chat.config.seed,
        stop=chat.config.stop,
        temperature=chat.config.temperature,
        user=chat.config.user,
    )
    assert chat_completion.choices[0].message.content or chat_completion.choices[0].message.tool_calls
    return chat_completion


async def execute(model: str, chat: Chat) -> LLMResult:
    try:
        if not chat.config or chat.prompt_type == PromptType.DEFAULT:
            chat.prompt_type = PromptType.DEFAULT
            response = await _generate(
                model=model, messages=chat.messages)
        elif chat.prompt_type == PromptType.OPENAI:
            response = await _generate_openai_with_params(chat)
        elif chat.prompt_type == PromptType.GROQ:
            response = await _generate_groq_with_params(chat)
        else:
            response = "Invalid promptType"
        return LLMResult(
            chat_completion=response,
            error="",
        )
    except APIError as api_error:
        print(f"OpenAI API error: {api_error}", flush=True)
        return LLMResult(
            chat_completion=None,
            error=api_error.message,
        )
    except Exception as e:
        print(f"LLM generation error: {e}", flush=True)
        return LLMResult(
            chat_completion=None,
            error=str(e),
        )
