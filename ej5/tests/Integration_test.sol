// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "remix_tests.sol";
import "./TraceabilityTestSupport.sol";

contract IntegrationTest is TraceabilityTestSupport {
    function beforeEach() public { _setUp(); }

    function testProducerFactoryDistributorFlow() public {
        uint256 tomatoBatchId = _createRawBatch();
        uint256 oilBatchId = _createBatch(producer, "Aceite", "Almazara", new uint256[](0));
        _transfer(tomatoBatchId, producer, factory, "Valencia");
        _transfer(oilBatchId, producer, factory, "Valencia");
        uint256[] memory ingredientIds = new uint256[](2);
        ingredientIds[0] = tomatoBatchId; ingredientIds[1] = oilBatchId;
        uint256 sauceBatchId = _createBatch(factory, "Salsa de tomate", "Valencia", ingredientIds);
        _transfer(sauceBatchId, factory, distributor, "Almacen Madrid");
        _callAs(distributor, abi.encodeCall(traceability.recordStep, (sauceBatchId, "Tienda Madrid")));
        FoodTraceability.Batch memory batch = _getBatch(sauceBatchId);
        Assert.equal(batch.name, "Salsa de tomate", "Nombre incorrecto");
        Assert.equal(batch.creator, address(factory), "Creador incorrecto");
        Assert.equal(batch.custodian, address(distributor), "Custodia final incorrecta");
        Assert.equal(batch.isProduct, true, "Debe ser producto");
        uint256[] memory ingredients = traceability.getIngredients(sauceBatchId);
        Assert.equal(ingredients.length, uint256(2), "Deben existir dos ingredientes");
        Assert.equal(ingredients[0], tomatoBatchId, "Origen tomate perdido");
        Assert.equal(ingredients[1], oilBatchId, "Origen aceite perdido");
        Assert.equal(traceability.stepCount(sauceBatchId), uint256(3), "Deben existir tres pasos");
        Assert.equal(_getStep(sauceBatchId, 0).location, "Valencia", "Origen incorrecto");
        Assert.equal(_getStep(sauceBatchId, 1).location, "Almacen Madrid", "Recepcion incorrecta");
        Assert.equal(_getStep(sauceBatchId, 2).location, "Tienda Madrid", "Destino incorrecto");
        Assert.equal(_getStep(sauceBatchId, 0).operator, address(factory), "Operador inicial incorrecto");
        Assert.equal(_getStep(sauceBatchId, 1).operator, address(distributor), "Operador de recepcion incorrecto");
        Assert.equal(_getStep(sauceBatchId, 2).operator, address(distributor), "Operador final incorrecto");
        Assert.equal(_getStep(tomatoBatchId, 0).location, "Finca", "No debe perderse origen del ingrediente");
    }

    function testProductCanBeAnotherProductsIngredient() public {
        uint256 tomatoBatchId = _createRawBatch();
        _transfer(tomatoBatchId, producer, factory, "Planta");
        uint256 sauceBatchId = _createBatch(factory, "Salsa", "Planta", _singleIngredient(tomatoBatchId));
        uint256 dishBatchId = _createBatch(factory, "Plato preparado", "Planta", _singleIngredient(sauceBatchId));
        uint256[] memory directIngredients = traceability.getIngredients(dishBatchId);
        Assert.equal(directIngredients.length, uint256(1), "Debe existir un ingrediente directo");
        Assert.equal(directIngredients[0], sauceBatchId, "Relacion plato-salsa incorrecta");
        uint256[] memory sourceIngredients = traceability.getIngredients(directIngredients[0]);
        Assert.equal(sourceIngredients.length, uint256(1), "Debe existir un ingrediente de salsa");
        Assert.equal(sourceIngredients[0], tomatoBatchId, "Relacion salsa-tomate incorrecta");
        Assert.ok(tomatoBatchId < sauceBatchId && sauceBatchId < dishBatchId, "La procedencia debe ser aciclica");
        Assert.equal(_getBatch(sourceIngredients[0]).creator, address(producer), "Origen incorrecto");
    }

    function testIngredientsCanBeReusedWithPendingProposal() public {
        // Documenta el alcance actual: no hay consumo de stock ni bloqueo por envio.
        uint256 tomatoBatchId = _createRawBatch();
        _propose(tomatoBatchId, producer, factory);
        _callAs(producer, abi.encodeCall(traceability.recordStep, (tomatoBatchId, "En espera")));
        uint256 firstOutputId = _createBatch(producer, "Salida 1", "Finca", _singleIngredient(tomatoBatchId));
        uint256 secondOutputId = _createBatch(producer, "Salida 2", "Finca", _singleIngredient(tomatoBatchId));
        Assert.equal(traceability.getIngredients(firstOutputId)[0], tomatoBatchId, "Primera salida incorrecta");
        Assert.equal(traceability.getIngredients(secondOutputId)[0], tomatoBatchId, "Segunda salida incorrecta");
        Assert.equal(_getBatch(tomatoBatchId).pendingRecipient, address(factory), "Debe conservar propuesta");
        Assert.equal(_getBatch(tomatoBatchId).custodian, address(producer), "Debe conservar custodio");
        Assert.equal(traceability.stepCount(tomatoBatchId), uint256(2), "Debe admitir paso mientras espera");
    }
}
