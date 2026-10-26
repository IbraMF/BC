// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "remix_tests.sol";
import "./TraceabilityTestSupport.sol";

contract TransfersTest is TraceabilityTestSupport {
    function beforeEach() public { _setUp(); _createRawBatch(); }

    function testRejectsInvalidRecipients() public {
        bytes memory expected = abi.encodeWithSelector(FoodTraceability.InvalidRecipient.selector);
        _expectRevert(producer, abi.encodeCall(traceability.proposeTransfer, (1, address(0))), expected);
        _expectRevert(producer, abi.encodeCall(traceability.proposeTransfer, (1, address(outsider))), expected);
        _expectRevert(producer, abi.encodeCall(traceability.proposeTransfer, (1, address(producer))), expected);
    }

    function testProposalPreservesCustodyAndCannotBeDuplicated() public {
        _propose(1, producer, factory);
        Assert.equal(_getBatch(1).custodian, address(producer), "Proponer no entrega la custodia");
        Assert.equal(_getBatch(1).pendingRecipient, address(factory), "Receptor incorrecto");
        Assert.equal(traceability.stepCount(1), uint256(1), "Proponer no registra recepcion");
        _expectRevert(producer, abi.encodeCall(traceability.proposeTransfer, (1, address(distributor))),
            abi.encodeWithSelector(FoodTraceability.TransferAlreadyPending.selector));
    }

    function testCancellationPreventsAcceptanceAndAllowsNewProposal() public {
        _propose(1, producer, factory);
        _callAs(producer, abi.encodeCall(traceability.cancelTransfer, (1)));
        Assert.equal(_getBatch(1).pendingRecipient, address(0), "Debe borrar la propuesta");
        Assert.equal(_getBatch(1).custodian, address(producer), "Cancelar conserva custodia");
        _expectRevert(factory, abi.encodeCall(traceability.acceptTransfer, (1, "X")),
            abi.encodeWithSelector(FoodTraceability.NotAssignedRecipient.selector));
        _propose(1, producer, distributor);
        Assert.equal(_getBatch(1).pendingRecipient, address(distributor), "Debe aceptar nueva propuesta");
    }

    function testOnlyAssignedRecipientCanAcceptOnce() public {
        bytes memory unassignedError = abi.encodeWithSelector(FoodTraceability.NotAssignedRecipient.selector);
        _expectRevert(factory, abi.encodeCall(traceability.acceptTransfer, (1, "X")), unassignedError);
        _propose(1, producer, factory);
        _expectRevert(distributor, abi.encodeCall(traceability.acceptTransfer, (1, "X")), unassignedError);
        _callAs(factory, abi.encodeCall(traceability.acceptTransfer, (1, "Planta")));
        Assert.equal(_getBatch(1).custodian, address(factory), "Custodia no actualizada");
        Assert.equal(_getBatch(1).creator, address(producer), "No debe cambiar el creador");
        Assert.equal(_getBatch(1).pendingRecipient, address(0), "No debe quedar propuesta");
        Assert.equal(traceability.stepCount(1), uint256(2), "Falta paso de recepcion");
        FoodTraceability.Step memory step = _getStep(1, 1);
        Assert.equal(step.operator, address(factory), "Receptor incorrecto en historial");
        Assert.equal(step.location, "Planta", "Ubicacion de recepcion incorrecta");
        Assert.equal(uint256(step.timestamp), block.timestamp, "Fecha incorrecta");
        _expectRevert(factory, abi.encodeCall(traceability.acceptTransfer, (1, "X")), unassignedError);
        _expectRevert(producer, abi.encodeCall(traceability.recordStep, (1, "X")),
            abi.encodeWithSelector(FoodTraceability.NotCustodian.selector, uint256(1)));
    }

    function testInvalidLocationPreservesProposal() public {
        _propose(1, producer, factory);
        bytes memory expected = abi.encodeWithSelector(FoodTraceability.InvalidText.selector);
        _expectRevert(producer, abi.encodeCall(traceability.recordStep, (1, "")), expected);
        _expectRevert(producer, abi.encodeCall(traceability.recordStep, (1, _repeat("U", 81))), expected);
        _expectRevert(factory, abi.encodeCall(traceability.acceptTransfer, (1, "")), expected);
        _expectRevert(factory, abi.encodeCall(traceability.acceptTransfer, (1, _repeat("U", 81))), expected);
        Assert.equal(_getBatch(1).pendingRecipient, address(factory), "Fallo no debe borrar propuesta");
        Assert.equal(_getBatch(1).custodian, address(producer), "Fallo no debe cambiar custodia");
        Assert.equal(traceability.stepCount(1), uint256(1), "Fallo no debe registrar pasos");
    }

    function testRevokedRecipientCannotAcceptAndCustodianCanCancel() public {
        _propose(1, producer, factory);
        traceability.setOperator(address(factory), false);
        _expectRevert(factory, abi.encodeCall(traceability.acceptTransfer, (1, "X")),
            abi.encodeWithSelector(FoodTraceability.UnauthorizedOperator.selector));
        _callAs(producer, abi.encodeCall(traceability.cancelTransfer, (1)));
        Assert.equal(_getBatch(1).pendingRecipient, address(0), "No se pudo cancelar");
    }

    function testProposalRemainsAcceptableAfterRevokingSender() public {
        // Politica actual: revocar al emisor no anula una propuesta ya creada.
        _propose(1, producer, factory);
        traceability.setOperator(address(producer), false);
        _callAs(factory, abi.encodeCall(traceability.acceptTransfer, (1, "Planta")));
        Assert.equal(_getBatch(1).custodian, address(factory), "Receptor autorizado debe poder aceptar");
    }

    function testCancellationWithoutProposalReverts() public {
        _expectRevert(producer, abi.encodeCall(traceability.cancelTransfer, (1)),
            abi.encodeWithSelector(FoodTraceability.NoPendingTransfer.selector));
        Assert.equal(_getBatch(1).custodian, address(producer), "Custodia debe conservarse");
    }
}
