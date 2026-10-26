// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "remix_tests.sol";
import "../FoodTraceability.sol";

/// @dev Actor exclusivo de pruebas: el contrato probado ve esta direccion como msg.sender.
contract TraceabilityActor {
    function execute(address target, bytes calldata data)
        external
        returns (bool success, bytes memory result)
    {
        return target.call(data);
    }
}

/// @dev Solo helpers internos: Remix no los interpreta como casos de prueba.
abstract contract TraceabilityTestSupport {
    FoodTraceability internal traceability;
    TraceabilityActor internal producer;
    TraceabilityActor internal factory;
    TraceabilityActor internal distributor;
    TraceabilityActor internal outsider;

    function _setUp() internal {
        // Quien despliega es esta suite, por tanto admin == address(this).
        traceability = new FoodTraceability();
        producer = new TraceabilityActor();
        factory = new TraceabilityActor();
        distributor = new TraceabilityActor();
        outsider = new TraceabilityActor();
        traceability.registerOperator(address(producer), "Productor");
        traceability.registerOperator(address(factory), "Fabrica");
        traceability.registerOperator(address(distributor), "Distribuidor");
    }

    function _callAs(TraceabilityActor actor, bytes memory data)
        internal
        returns (bytes memory result)
    {
        bool success;
        (success, result) = actor.execute(address(traceability), data);
        // Una operacion positiva inesperadamente revertida hace fallar el test.
        require(success, "Operacion positiva revertida");
    }

    function _expectRevert(TraceabilityActor actor, bytes memory data, bytes memory expected)
        internal
    {
        (bool success, bytes memory result) = actor.execute(address(traceability), data);
        Assert.equal(success, false, "La operacion debia revertir");
        // Compara selector Y argumentos del error personalizado.
        Assert.equal(keccak256(result), keccak256(expected), "Error de reversion incorrecto");
    }

    function _expectDirectRevert(bytes memory data, bytes memory expected) internal {
        (bool success, bytes memory result) = address(traceability).call(data);
        Assert.equal(success, false, "La operacion debia revertir");
        Assert.equal(keccak256(result), keccak256(expected), "Error de reversion incorrecto");
    }

    function _createBatch(TraceabilityActor actor, string memory name, string memory location, uint256[] memory ingredientIds)
        internal
        returns (uint256)
    {
        return abi.decode(_callAs(actor, abi.encodeCall(traceability.createBatch, (name, location, ingredientIds))), (uint256));
    }

    function _createRawBatch() internal returns (uint256) {
        return _createBatch(producer, "Tomate", "Finca", new uint256[](0));
    }

    function _singleIngredient(uint256 id) internal pure returns (uint256[] memory ingredientIds) {
        ingredientIds = new uint256[](1);
        ingredientIds[0] = id;
    }

    function _propose(uint256 id, TraceabilityActor from, TraceabilityActor to) internal {
        _callAs(from, abi.encodeCall(traceability.proposeTransfer, (id, address(to))));
    }

    function _transfer(uint256 id, TraceabilityActor from, TraceabilityActor to, string memory location)
        internal
    {
        _propose(id, from, to);
        _callAs(to, abi.encodeCall(traceability.acceptTransfer, (id, location)));
    }

    function _getBatch(uint256 id) internal view returns (FoodTraceability.Batch memory batch) {
        (batch.name, batch.creator, batch.custodian, batch.pendingRecipient, batch.createdAt, batch.isProduct) = traceability.batches(id);
    }

    function _getStep(uint256 id, uint256 index) internal view returns (FoodTraceability.Step memory step) {
        (step.operator, step.timestamp, step.location) = traceability.getStep(id, index);
    }

    function _repeat(string memory text, uint256 count) internal pure returns (string memory) {
        bytes memory pattern = bytes(text);
        bytes memory result = new bytes(pattern.length * count);
        for (uint256 i; i < result.length; ++i) result[i] = pattern[i % pattern.length];
        return string(result);
    }
}
