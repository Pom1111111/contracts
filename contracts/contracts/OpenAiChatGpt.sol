// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

interface IOracle {
    struct OpenAiRequest {
        string model;
        int8 frequencyPenalty;
        string logitBias;
        uint32 maxTokens;
        int8 presencePenalty;
        string responseFormat;
        uint seed;
        string stop;
        uint temperature;
        uint topP;
        string tools;
        string toolChoice;
        string user;
    }

    struct OpenAiResponse {
        string id;

        string content;
        string functionName;
        string functionArguments;

        uint64 created;
        string model;
        string systemFingerprint;
        string object;

        uint32 completionTokens;
        uint32 promptTokens;
        uint32 totalTokens;
    }

    function createOpenAiLlmCall(
        uint promptId,
        OpenAiRequest memory request
    ) external returns (uint);

    function createFunctionCall(
        uint functionCallbackId,
        string memory functionType,
        string memory functionInput
    ) external returns (uint i);
}

contract OpenAiChatGpt {

    struct Message {
        string role;
        string content;
    }

    struct ChatRun {
        address owner;
        Message[] messages;
        uint messagesCount;
    }

    mapping(uint => ChatRun) public chatRuns;
    uint private chatRunsCount;

    event ChatCreated(address indexed owner, uint indexed chatId);

    address private owner;
    address public oracleAddress;

    event OracleAddressUpdated(address indexed newOracleAddress);

    IOracle.OpenAiRequest private config;

    constructor(address initialOracleAddress) {
        owner = msg.sender;
        oracleAddress = initialOracleAddress;
        chatRunsCount = 0;

        config = IOracle.OpenAiRequest({
        model : "gpt-4-turbo-preview",
        frequencyPenalty : 21, // > 20 for null
        logitBias : "", // empty str for null
        maxTokens : 1000, // 0 for null
        presencePenalty : 21, // > 20 for null
        responseFormat : "{\"type\":\"text\"}",
        seed : 0, // null
        stop : "", // null
        temperature : 10, // Example temperature (scaled up, 10 means 1.0), > 20 means null
        topP : 101, // Percentage 0-100, > 100 means null
        tools : "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}}]",
        toolChoice : "auto", // "none" or "auto"
        user : "" // null
        });
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Caller is not oracle");
        _;
    }

    function setOracleAddress(address newOracleAddress) public onlyOwner {
        oracleAddress = newOracleAddress;
        emit OracleAddressUpdated(newOracleAddress);
    }

    function startChat(string memory message) public returns (uint i) {
        ChatRun storage run = chatRuns[chatRunsCount];

        run.owner = msg.sender;
        Message memory newMessage;
        newMessage.content = message;
        newMessage.role = "user";
        run.messages.push(newMessage);
        run.messagesCount = 1;

        uint currentId = chatRunsCount;
        chatRunsCount = chatRunsCount + 1;

        IOracle(oracleAddress).createOpenAiLlmCall(currentId, config);
        emit ChatCreated(msg.sender, currentId);

        return currentId;
    }

    function onOracleOpenAiLlmResponse(
        uint runId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("user")),
            "No message to respond to"
        );

        if (!compareStrings(errorMessage, "")) {
            Message memory newMessage;
            newMessage.role = "assistant";
            newMessage.content = errorMessage;
            run.messages.push(newMessage);
            run.messagesCount++;
        } else {
            if (compareStrings(response.content, "")) {
                IOracle(oracleAddress).createFunctionCall(runId, response.functionName, response.functionArguments);
            } else {
                Message memory newMessage;
                newMessage.role = "assistant";
                newMessage.content = response.content;
                run.messages.push(newMessage);
                run.messagesCount++;
            }
        }
    }

    function onOracleFunctionResponse(
        uint runId,
        string memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            compareStrings(run.messages[run.messagesCount - 1].role, "user"),
            "No function to respond to"
        );
        if (compareStrings(errorMessage, "")) {
            Message memory newMessage;
            newMessage.role = "user";
            newMessage.content = response;
            run.messages.push(newMessage);
            run.messagesCount++;
            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }
    }

    function addMessage(string memory message, uint runId) public {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("assistant")),
            "No response to previous message"
        );
        require(
            run.owner == msg.sender, "Only chat owner can add messages"
        );

        Message memory newMessage;
        newMessage.content = message;
        newMessage.role = "user";
        run.messages.push(newMessage);
        run.messagesCount++;

        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    function getMessageHistoryContents(uint chatId) public view returns (string[] memory) {
        string[] memory messages = new string[](chatRuns[chatId].messages.length);
        for (uint i = 0; i < chatRuns[chatId].messages.length; i++) {
            messages[i] = chatRuns[chatId].messages[i].content;
        }
        return messages;
    }

    function getMessageHistoryRoles(uint chatId) public view returns (string[] memory) {
        string[] memory roles = new string[](chatRuns[chatId].messages.length);
        for (uint i = 0; i < chatRuns[chatId].messages.length; i++) {
            roles[i] = chatRuns[chatId].messages[i].role;
        }
        return roles;
    }

    function compareStrings(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
