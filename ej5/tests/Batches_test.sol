// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "remix_tests.sol";
import "./TraceabilityTestSupport.sol";

contract BatchesTest is TraceabilityTestSupport {
    function beforeEach() public { _setUp(); }

    function testRawBatchDataAndInitialStep() public {
        uint256 id = _createRawBatch();
        FoodTraceability.Batch memory batch = _getBatch(id);
        Assert.equal(id, uint256(1), "Primer ID incorrecto");
        Assert.equal(traceability.nextBatchId(), uint256(2), "Contador incorrecto");
        Assert.equal(batch.name, "Tomate", "Nombre incorrecto");
        Assert.equal(batch.creator, address(producer), "Creador incorrecto");
        Assert.equal(batch.custodian, address(producer), "Custodio incorrecto");
        Assert.equal(batch.pendingRecipient, address(0), "No debe haber receptor");
        Assert.equal(batch.isProduct, false, "Una materia prima no tiene ingredientes");
        Assert.equal(uint256(batch.createdAt), block.timestamp, "Fecha incorrecta");
        Assert.equal(traceability.getIngredients(id).length, uint256(0), "Ingredientes inesperados");
        Assert.equal(traceability.stepCount(id), uint256(1), "Falta paso inicial");
        FoodTraceability.Step memory step = _getStep(id, 0);
        Assert.equal(step.operator, address(producer), "Operador incorrecto");
        Assert.equal(uint256(step.timestamp), block.timestamp, "Fecha del paso incorrecta");
        Assert.equal(step.location, "Finca", "Ubicacion incorrecta");
    }

    function testProductAcceptsUnsortedIngredients() public {
        _createRawBatch(); _createRawBatch();
        uint256[] memory ingredientIds = new uint256[](2);
        ingredientIds[0] = 2; ingredientIds[1] = 1;
        uint256 id = _createBatch(producer, "Salsa", "Planta", ingredientIds);
        Assert.equal(id, uint256(3), "ID del producto incorrecto");
        Assert.equal(_getBatch(id).isProduct, true, "Debe ser producto");
        uint256[] memory storedIngredients = traceability.getIngredients(id);
        Assert.equal(storedIngredients.length, uint256(2), "Numero de ingredientes incorrecto");
        Assert.equal(storedIngredients[0], uint256(2), "No debe reordenar ingredientes");
        Assert.equal(storedIngredients[1], uint256(1), "Segundo ingrediente incorrecto");
    }

    function testRejectsEmptyAndOversizedText() public {
        bytes memory invalidTextError = abi.encodeWithSelector(FoodTraceability.InvalidText.selector);
        uint256[] memory emptyIngredients = new uint256[](0);
        _expectRevert(producer, abi.encodeCall(traceability.createBatch, ("", "F", emptyIngredients)), invalidTextError);
        _expectRevert(producer, abi.encodeCall(traceability.createBatch, ("X", "", emptyIngredients)), invalidTextError);
        _expectRevert(producer, abi.encodeCall(traceability.createBatch, (_repeat("N", 65), "F", emptyIngredients)), invalidTextError);
        _expectRevert(producer, abi.encodeCall(traceability.createBatch, ("X", _repeat("U", 81), emptyIngredients)), invalidTextError);
        Assert.equal(traceability.nextBatchId(), uint256(1), "Un error no debe avanzar el ID");
    }

    function testTextLimitsUseUtf8Bytes() public {
        uint256 id = _createBatch(producer, _repeat("N", 64), _repeat("U", 80), new uint256[](0));
        Assert.equal(bytes(_getBatch(id).name).length, uint256(64), "Nombre limite incorrecto");
        Assert.equal(bytes(_getStep(id, 0).location).length, uint256(80), "Ubicacion limite incorrecta");
        uint256 utf8BatchId = _createBatch(producer, _repeat(unicode"á", 32), "F", new uint256[](0));
        Assert.equal(bytes(_getBatch(utf8BatchId).name).length, uint256(64), "32 caracteres deben ocupar 64 bytes");
        _expectRevert(producer,
            abi.encodeCall(traceability.createBatch, (_repeat(unicode"á", 33), "F", new uint256[](0))),
            abi.encodeWithSelector(FoodTraceability.InvalidText.selector));
    }

    function testRejectsZeroSelfAndFutureIngredients() public {
        _createRawBatch();
        uint256[3] memory invalidIds = [uint256(0), uint256(2), uint256(999)];
        for (uint256 i; i < invalidIds.length; ++i) {
            _expectRevert(producer, abi.encodeCall(traceability.createBatch, ("X", "F", _singleIngredient(invalidIds[i]))),
                abi.encodeWithSelector(FoodTraceability.InvalidIngredient.selector, invalidIds[i]));
        }
    }

    function testDuplicatesRollBackPartialWrites() public {
        _createRawBatch();
        uint256[] memory ingredientIds = new uint256[](2);
        ingredientIds[0] = 1; ingredientIds[1] = 1;
        _expectRevert(producer, abi.encodeCall(traceability.createBatch, ("X", "F", ingredientIds)),
            abi.encodeWithSelector(FoodTraceability.DuplicateIngredient.selector, uint256(1)));
        Assert.equal(traceability.nextBatchId(), uint256(2), "No debe avanzar el contador");
        Assert.equal(_createRawBatch(), uint256(2), "El ID fallido debe poder reutilizarse");
        Assert.equal(traceability.getIngredients(2).length, uint256(0), "Quedan ingredientes parciales");
        Assert.equal(traceability.stepCount(2), uint256(1), "Quedan pasos parciales");
    }

    function testAcceptsTwentyIngredientsAndRejectsTwentyOne() public {
        uint256[] memory ingredientIds = new uint256[](20);
        for (uint256 i; i < ingredientIds.length; ++i) ingredientIds[i] = _createRawBatch();
        uint256 productBatchId = _createBatch(producer, "Salsa", "Planta", ingredientIds);
        uint256[] memory storedIngredients = traceability.getIngredients(productBatchId);
        Assert.equal(storedIngredients.length, uint256(20), "Debe aceptar 20 ingredientes");
        for (uint256 i; i < ingredientIds.length; ++i) Assert.equal(storedIngredients[i], ingredientIds[i], "Ingrediente incorrecto");
        uint256[] memory tooMany = new uint256[](21);
        for (uint256 i; i < tooMany.length; ++i) tooMany[i] = i + 1;
        _expectRevert(producer, abi.encodeCall(traceability.createBatch, ("X", "F", tooMany)),
            abi.encodeWithSelector(FoodTraceability.TooManyIngredients.selector));
        Assert.equal(traceability.nextBatchId(), uint256(22), "El fallo no debe avanzar el ID");
    }

    function testRecordingStepPreservesHistory() public {
        uint256 id = _createRawBatch();
        _callAs(producer, abi.encodeCall(traceability.recordStep, (id, "Almacen")));
        Assert.equal(traceability.stepCount(id), uint256(2), "Deben existir dos pasos");
        Assert.equal(_getStep(id, 0).location, "Finca", "Se ha cambiado el origen");
        FoodTraceability.Step memory step = _getStep(id, 1);
        Assert.equal(step.location, "Almacen", "Segundo paso incorrecto");
        Assert.equal(step.operator, address(producer), "Operador incorrecto");
        Assert.equal(uint256(step.timestamp), block.timestamp, "Fecha incorrecta");
    }

    function testQueriesRejectMissingBatchesAndInvalidIndexes() public {
        bytes memory notFoundError = abi.encodeWithSelector(FoodTraceability.BatchNotFound.selector, uint256(999));
        _expectDirectRevert(abi.encodeCall(traceability.getIngredients, (999)), notFoundError);
        _expectDirectRevert(abi.encodeCall(traceability.stepCount, (999)), notFoundError);
        _expectDirectRevert(abi.encodeCall(traceability.getStep, (999, 0)), notFoundError);
        _createRawBatch();
        _expectDirectRevert(abi.encodeCall(traceability.getStep, (1, 1)),
            abi.encodeWithSelector(FoodTraceability.StepNotFound.selector, uint256(1), uint256(1)));
        Assert.equal(_getBatch(999).creator, address(0), "El getter del mapping debe devolver cero");
    }

    function testPublicQueriesDoNotRequireAuthorization() public {
        _createRawBatch();
        Assert.equal(traceability.operators(address(outsider)), false, "El lector no debe estar autorizado");
        bytes memory result = _callAs(outsider, abi.encodeCall(traceability.stepCount, (1)));
        Assert.equal(abi.decode(result, (uint256)), uint256(1), "La consulta publica debe funcionar");
        result = _callAs(outsider, abi.encodeCall(traceability.getIngredients, (1)));
        Assert.equal(abi.decode(result, (uint256[])).length, uint256(0), "Ingredientes inesperados");
        result = _callAs(outsider, abi.encodeCall(traceability.getStep, (1, 0)));
        (address operator,, string memory location) = abi.decode(result, (address, uint64, string));
        Assert.equal(operator, address(producer), "Operador publico incorrecto");
        Assert.equal(location, "Finca", "Paso publico incorrecto");
    }
}
