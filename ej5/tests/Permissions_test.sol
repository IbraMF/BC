// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "remix_tests.sol";
import "remix_accounts.sol";
import "./TraceabilityTestSupport.sol";

contract PermissionsTest is TraceabilityTestSupport {
    function beforeEach() public { _setUp(); }

    function testConstructorAssignsAdminAndOperator() public {
        Assert.equal(traceability.admin(), address(this), "El administrador es quien despliega");
        Assert.equal(traceability.operators(address(this)), true, "Administrador debe ser operador");
        Assert.equal(traceability.operatorNames(address(this)), "Administrador", "Nombre inicial incorrecto");
        Assert.equal(traceability.operators(address(outsider)), false, "Intruso no autorizado");
        Assert.equal(traceability.nextBatchId(), uint256(1), "Contador inicial incorrecto");
    }

    function testOnlyAdminCanConfigureOperators() public {
        _expectRevert(producer, abi.encodeCall(traceability.setOperator, (address(outsider), true)),
            abi.encodeWithSelector(FoodTraceability.OnlyAdmin.selector));
        _expectDirectRevert(abi.encodeCall(traceability.setOperator, (address(0), true)),
            abi.encodeWithSelector(FoodTraceability.InvalidAddress.selector));
        traceability.setOperator(address(outsider), true);
        Assert.equal(traceability.operators(address(outsider)), true, "Alta no aplicada");
        traceability.setOperator(address(outsider), false);
        Assert.equal(traceability.operators(address(outsider)), false, "Revocacion no aplicada");
    }

    function testAdminCanRegisterNamedOperator() public {
        traceability.registerOperator(address(outsider), "Cooperativa del Sur");
        Assert.equal(traceability.operators(address(outsider)), true, "Debe autorizar al operador");
        Assert.equal(traceability.operatorNames(address(outsider)), "Cooperativa del Sur", "Nombre incorrecto");
        uint256 id = _createBatch(outsider, "Tomate", "Finca", new uint256[](0));
        Assert.equal(_getBatch(id).creator, address(outsider), "El operador registrado debe poder crear lotes");
    }

    function testOnlyAdminCanRegisterNamedOperators() public {
        bytes memory expected = abi.encodeWithSelector(FoodTraceability.OnlyAdmin.selector);
        _expectRevert(producer, abi.encodeCall(traceability.registerOperator, (address(outsider), "Intruso")), expected);
        _expectRevert(producer, abi.encodeCall(traceability.registerOperator, (address(producer), "Nombre cambiado")), expected);
        Assert.equal(traceability.operators(address(outsider)), false, "No debe autorizar a un intruso");
        Assert.equal(traceability.operatorNames(address(outsider)), "", "No debe escribir un nombre");
        Assert.equal(traceability.operatorNames(address(producer)), "Productor", "Un operador no puede cambiar su nombre");
    }

    function testOperatorNameValidation() public {
        bytes memory invalidText = abi.encodeWithSelector(FoodTraceability.InvalidText.selector);
        _expectDirectRevert(abi.encodeCall(traceability.registerOperator, (address(0), "Empresa")),
            abi.encodeWithSelector(FoodTraceability.InvalidAddress.selector));
        _expectDirectRevert(abi.encodeCall(traceability.registerOperator, (address(outsider), "")), invalidText);
        _expectDirectRevert(abi.encodeCall(traceability.registerOperator, (address(outsider), _repeat("N", 65))), invalidText);
        Assert.equal(traceability.operators(address(outsider)), false, "Un nombre invalido no debe autorizar");
        Assert.equal(traceability.operatorNames(address(outsider)), "", "Un fallo no debe guardar el nombre");
        traceability.registerOperator(address(outsider), _repeat("N", 64));
        Assert.equal(bytes(traceability.operatorNames(address(outsider))).length, uint256(64), "Debe aceptar 64 bytes");
        string memory name = _repeat(unicode"á", 32);
        traceability.registerOperator(address(outsider), name);
        Assert.equal(traceability.operatorNames(address(outsider)), name, "Debe aceptar nombres UTF-8 de 64 bytes");
        _expectDirectRevert(abi.encodeCall(traceability.registerOperator, (address(outsider), _repeat(unicode"á", 33))), invalidText);
        Assert.equal(traceability.operatorNames(address(outsider)), name, "Un fallo debe conservar el nombre anterior");
    }

    function testRevocationPreservesOperatorName() public {
        traceability.registerOperator(address(outsider), "Cooperativa del Sur");
        traceability.setOperator(address(outsider), false);
        Assert.equal(traceability.operators(address(outsider)), false, "Debe revocar el acceso");
        Assert.equal(traceability.operatorNames(address(outsider)), "Cooperativa del Sur", "Debe conservar el nombre");
        bytes memory result = _callAs(outsider, abi.encodeCall(traceability.operatorNames, (address(outsider))));
        Assert.equal(abi.decode(result, (string)), "Cooperativa del Sur", "El nombre debe ser de consulta publica");
        _expectRevert(outsider, abi.encodeCall(traceability.createBatch, ("X", "F", new uint256[](0))),
            abi.encodeWithSelector(FoodTraceability.UnauthorizedOperator.selector));
    }

    function testRegisteringAgainUpdatesNameAndReauthorizes() public {
        traceability.registerOperator(address(outsider), "Nombre anterior");
        traceability.registerOperator(address(outsider), "Nombre actualizado");
        Assert.equal(traceability.operatorNames(address(outsider)), "Nombre actualizado", "Debe actualizar el nombre");
        traceability.setOperator(address(outsider), false);
        traceability.registerOperator(address(outsider), "Nombre final");
        Assert.equal(traceability.operators(address(outsider)), true, "Registrar de nuevo debe reautorizar");
        Assert.equal(traceability.operatorNames(address(outsider)), "Nombre final", "Nombre final incorrecto");
    }

    function testUnauthorizedAccountCannotWrite() public {
        _createRawBatch();
        bytes memory permissionError = abi.encodeWithSelector(FoodTraceability.UnauthorizedOperator.selector);
        _expectRevert(outsider, abi.encodeCall(traceability.createBatch, ("X", "F", new uint256[](0))), permissionError);
        _expectRevert(outsider, abi.encodeCall(traceability.recordStep, (1, "X")), permissionError);
        _expectRevert(outsider, abi.encodeCall(traceability.proposeTransfer, (1, address(factory))), permissionError);
        _expectRevert(outsider, abi.encodeCall(traceability.cancelTransfer, (1)), permissionError);
        _expectRevert(outsider, abi.encodeCall(traceability.acceptTransfer, (1, "X")), permissionError);
    }

    function testOperatorCannotModifyAnotherCustodiansBatch() public {
        _createRawBatch();
        bytes memory custodyError = abi.encodeWithSelector(FoodTraceability.NotCustodian.selector, uint256(1));
        _expectRevert(factory, abi.encodeCall(traceability.recordStep, (1, "X")), custodyError);
        _expectRevert(factory, abi.encodeCall(traceability.proposeTransfer, (1, address(distributor))), custodyError);
        _expectRevert(factory, abi.encodeCall(traceability.cancelTransfer, (1)), custodyError);
        _expectRevert(factory, abi.encodeCall(traceability.createBatch, ("X", "F", _singleIngredient(1))), custodyError);
        bytes memory notFoundError = abi.encodeWithSelector(FoodTraceability.BatchNotFound.selector, uint256(999));
        _expectRevert(producer, abi.encodeCall(traceability.recordStep, (999, "X")), notFoundError);
        _expectRevert(producer, abi.encodeCall(traceability.proposeTransfer, (999, address(factory))), notFoundError);
        _expectRevert(producer, abi.encodeCall(traceability.cancelTransfer, (999)), notFoundError);
        _expectRevert(producer, abi.encodeCall(traceability.acceptTransfer, (999, "X")), notFoundError);
    }

    function testRevokeAndReauthorizeCustodian() public {
        _createRawBatch();
        traceability.setOperator(address(producer), false);
        _expectRevert(producer, abi.encodeCall(traceability.recordStep, (1, "X")),
            abi.encodeWithSelector(FoodTraceability.UnauthorizedOperator.selector));
        traceability.setOperator(address(producer), true);
        _callAs(producer, abi.encodeCall(traceability.recordStep, (1, "X")));
        Assert.equal(traceability.stepCount(1), uint256(2), "No se recupero acceso");
    }

    /// #sender: account-1
    function testRemixSenderDoesNotImpersonateInternalCaller() public {
        Assert.equal(msg.sender, TestsAccounts.getAccount(1), "Remix debe usar account-1");
        // Aunque account-1 ejecuta este test, el despliegue lo realizo la suite.
        Assert.equal(traceability.admin(), address(this), "El administrador sigue siendo la suite");
        Assert.notEqual(traceability.admin(), msg.sender, "El EOA no es el administrador del contrato nuevo");
        _createRawBatch();
        Assert.equal(_getBatch(1).creator, address(producer), "El contrato debe ver al actor productor");
    }
}
