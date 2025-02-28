// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/samples/SimpleAccount.sol";
import {SENTINEL_VALUE} from "modular-account/libraries/Constants.sol";
import {LinkedListSet, LinkedListSetLib} from "modular-account/libraries/LinkedListSetLib.sol";

import {BaseLightAccount} from "../src/common/BaseLightAccount.sol";
import {MultiOwnerLightAccount} from "../src/MultiOwnerLightAccount.sol";
import {MultiOwnerLightAccountFactory} from "../src/MultiOwnerLightAccountFactory.sol";

contract MultiOwnerLightAccountTest is Test {
    using stdStorage for StdStorage;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using LinkedListSetLib for LinkedListSet;

    uint256 public constant EOA_PRIVATE_KEY = 1;
    address payable public constant BENEFICIARY = payable(address(0xbe9ef1c1a2ee));
    bytes32 internal constant _MESSAGE_TYPEHASH = keccak256("LightAccountMessage(bytes message)");
    address public eoaAddress;
    MultiOwnerLightAccount public account;
    MultiOwnerLightAccount public contractOwnedAccount;
    EntryPoint public entryPoint;
    LightSwitch public lightSwitch;
    Owner public contractOwner;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event OwnersUpdated(address[] ownersToAdd, address[] ownersToRemove);
    event Initialized(uint64 version);

    function setUp() public {
        eoaAddress = vm.addr(EOA_PRIVATE_KEY);
        entryPoint = new EntryPoint();
        MultiOwnerLightAccountFactory factory = new MultiOwnerLightAccountFactory(address(this), entryPoint);
        account = factory.createAccountSingle(eoaAddress, 1);
        vm.deal(address(account), 1 << 128);
        lightSwitch = new LightSwitch();
        contractOwner = new Owner();
    }

    function testExecuteCanBeCalledByOwner() public {
        vm.prank(eoaAddress);
        account.execute(address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()));
        assertTrue(lightSwitch.on());
    }

    function testExecuteWithValueCanBeCalledByOwner() public {
        vm.prank(eoaAddress);
        account.execute(address(lightSwitch), 1 ether, abi.encodeCall(LightSwitch.turnOn, ()));
        assertTrue(lightSwitch.on());
        assertEq(address(lightSwitch).balance, 1 ether);
    }

    function testExecuteCanBeCalledByEntryPointWithExternalOwner() public {
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()))),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);
        assertTrue(lightSwitch.on());
    }

    function testExecuteCanBeCalledByEntryPointWithContractOwnerSpecified() public {
        _useContractOwner();
        PackedUserOperation memory op = _getUnsignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ())))
        );
        op.signature = abi.encodePacked(
            BaseLightAccount.SignatureType.CONTRACT_WITH_ADDR,
            contractOwner,
            contractOwner.sign(entryPoint.getUserOpHash(op))
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);
        assertTrue(lightSwitch.on());
    }

    function testRejectsUserOpsWithInvalidSignature() public {
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()))),
            1234
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, BENEFICIARY);
    }

    function testRejectsUserOpWithContractOwnerUnspecified() public {
        _useContractOwner();
        PackedUserOperation memory op = _getUnsignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ())))
        );
        op.signature =
            abi.encodePacked(BaseLightAccount.SignatureType.CONTRACT, contractOwner.sign(entryPoint.getUserOpHash(op)));
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodePacked(BaseLightAccount.InvalidSignatureType.selector)
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);
    }

    function testRejectsUserOpWithInvalidContractOwnerSpecified() public {
        PackedUserOperation memory op = _getUnsignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ())))
        );
        op.signature = abi.encodePacked(
            BaseLightAccount.SignatureType.CONTRACT_WITH_ADDR,
            contractOwner,
            contractOwner.sign(entryPoint.getUserOpHash(op))
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, BENEFICIARY);
        assertFalse(lightSwitch.on());
    }

    function testRejectsUserOpWithPartialContractOwnerSpecified() public {
        _useContractOwner();
        PackedUserOperation memory op = _getUnsignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ())))
        );
        op.signature = abi.encodePacked(
            BaseLightAccount.SignatureType.CONTRACT_WITH_ADDR, bytes10(bytes20(address(contractOwner)))
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOpWithRevert.selector, 0, "AA23 reverted", bytes("")));
        entryPoint.handleOps(ops, BENEFICIARY);
        assertFalse(lightSwitch.on());
    }

    function testFuzz_rejectsUserOpsWithInvalidSignatureType(uint8 signatureType) public {
        signatureType = uint8(bound(signatureType, 3, type(uint8).max));

        PackedUserOperation memory op = _getUnsignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ())))
        );
        op.signature = abi.encodePacked(signatureType);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodePacked(BaseLightAccount.InvalidSignatureType.selector)
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);
    }

    function testRevertsUserOpsWithMalformedSignature() public {
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()))),
            1234
        );
        op.signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, hex"aaaa");
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, (op.signature.length - 1))
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);

        op.signature = abi.encodePacked(uint8(3));
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodeWithSelector(BaseLightAccount.InvalidSignatureType.selector)
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);

        op.signature = hex"";
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodeWithSelector(BaseLightAccount.InvalidSignatureType.selector)
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);
    }

    function testExecuteCannotBeCalledByRandos() public {
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, (address(this))));
        account.execute(address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()));
    }

    function testWithdrawDepositToZeroAddress() public {
        account.addDeposit{value: 10}();
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.ZeroAddressNotAllowed.selector));
        account.withdrawDepositTo(payable(address(0)), 5);
    }

    function testExecuteRevertingCallShouldRevertWithSameData() public {
        Reverter reverter = new Reverter();
        vm.prank(eoaAddress);
        vm.expectRevert("did revert");
        account.execute(address(reverter), 0, abi.encodeCall(Reverter.doRevert, ()));
    }

    function testExecuteBatchCalledByOwner() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](1);
        dest[0] = address(lightSwitch);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        account.executeBatch(dest, func);
        assertTrue(lightSwitch.on());
    }

    function testExecuteBatchFailsForUnevenInputArrays() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](2);
        dest[0] = address(lightSwitch);
        dest[1] = address(lightSwitch);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        vm.expectRevert(BaseLightAccount.ArrayLengthMismatch.selector);
        account.executeBatch(dest, func);
    }

    function testExecuteBatchWithValueCalledByOwner() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](1);
        dest[0] = address(lightSwitch);
        uint256[] memory value = new uint256[](1);
        value[0] = uint256(1);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        account.executeBatch(dest, value, func);
        assertTrue(lightSwitch.on());
        assertEq(address(lightSwitch).balance, 1);
    }

    function testExecuteBatchWithValueFailsForUnevenInputArrays() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](1);
        dest[0] = address(lightSwitch);
        uint256[] memory value = new uint256[](2);
        value[0] = uint256(1);
        value[1] = uint256(1 ether);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        vm.expectRevert(BaseLightAccount.ArrayLengthMismatch.selector);
        account.executeBatch(dest, value, func);
    }

    function testInitialize() public {
        MultiOwnerLightAccountFactory factory = new MultiOwnerLightAccountFactory(address(this), entryPoint);
        vm.expectEmit(true, false, false, false);
        emit Initialized(0);
        account = factory.createAccountSingle(eoaAddress, 1);
    }

    function testCannotInitializeWithZeroOwner() public {
        MultiOwnerLightAccountFactory factory = new MultiOwnerLightAccountFactory(address(this), entryPoint);
        vm.expectRevert(MultiOwnerLightAccountFactory.InvalidOwners.selector);
        account = factory.createAccountSingle(address(0), 1);
    }

    function testAddDeposit() public {
        assertEq(account.getDeposit(), 0);
        account.addDeposit{value: 10}();
        assertEq(account.getDeposit(), 10);
        assertEq(account.getDeposit(), entryPoint.balanceOf(address(account)));
    }

    function testWithdrawDepositToCalledByOwner() public {
        account.addDeposit{value: 10}();
        vm.prank(eoaAddress);
        account.withdrawDepositTo(BENEFICIARY, 5);
        assertEq(entryPoint.balanceOf(address(account)), 5);
    }

    function testWithdrawDepositCanBeCalledByEntryPointWithExternalOwner() public {
        account.addDeposit{value: 1 ether}();
        address payable withdrawalAddress = payable(address(1));

        PackedUserOperation memory op =
            _getSignedOp(abi.encodeCall(BaseLightAccount.withdrawDepositTo, (withdrawalAddress, 5)), EOA_PRIVATE_KEY);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);

        assertEq(withdrawalAddress.balance, 5);
    }

    function testWithdrawDepositCanBeCalledBySelf() public {
        account.addDeposit{value: 1 ether}();
        address payable withdrawalAddress = payable(address(1));

        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(
                BaseLightAccount.execute,
                (address(account), 0, abi.encodeCall(BaseLightAccount.withdrawDepositTo, (withdrawalAddress, 5)))
            ),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);

        assertEq(withdrawalAddress.balance, 5);
    }

    function testWithdrawDepositToCannotBeCalledByRandos() public {
        account.addDeposit{value: 10}();
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, (address(this))));
        account.withdrawDepositTo(BENEFICIARY, 5);
    }

    function testOwnerCanUpdateOwners() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(0x100);
        address[] memory ownersToRemove = new address[](1);
        ownersToRemove[0] = eoaAddress;
        vm.prank(eoaAddress);

        vm.expectEmit(true, true, false, false);
        emit OwnersUpdated(ownersToAdd, ownersToRemove);
        account.updateOwners(ownersToAdd, ownersToRemove);
        assertEq(account.owners(), ownersToAdd);
    }

    function testEntryPointCanUpdateOwners() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(0x100);
        address[] memory ownersToRemove = new address[](1);
        ownersToRemove[0] = eoaAddress;
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(MultiOwnerLightAccount.updateOwners, (ownersToAdd, ownersToRemove)), EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectEmit(true, true, false, false);
        emit OwnersUpdated(ownersToAdd, ownersToRemove);
        entryPoint.handleOps(ops, BENEFICIARY);
        assertEq(account.owners(), ownersToAdd);
    }

    function testSelfCanUpdateOwners() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(0x100);
        address[] memory ownersToRemove = new address[](1);
        ownersToRemove[0] = eoaAddress;
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(
                BaseLightAccount.execute,
                (
                    address(account),
                    0,
                    abi.encodeCall(MultiOwnerLightAccount.updateOwners, (ownersToAdd, ownersToRemove))
                )
            ),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectEmit(true, true, false, false);
        emit OwnersUpdated(ownersToAdd, ownersToRemove);
        entryPoint.handleOps(ops, BENEFICIARY);
        assertEq(account.owners(), ownersToAdd);
    }

    function testRandosCannotUpdateOwners() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(0x100);
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, (address(this))));
        account.updateOwners(ownersToAdd, new address[](0));
    }

    function testCannotAddExistingOwner() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(eoaAddress);
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(MultiOwnerLightAccount.InvalidOwner.selector, (eoaAddress)));
        account.updateOwners(ownersToAdd, new address[](0));
    }

    function testCannotAddZeroAddressAsOwner() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(0);
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(MultiOwnerLightAccount.InvalidOwner.selector, (address(0))));
        account.updateOwners(ownersToAdd, new address[](0));
    }

    function testCannotRemoveAllOwners() public {
        address[] memory ownersToRemove = new address[](1);
        ownersToRemove[0] = address(eoaAddress);
        vm.prank(eoaAddress);
        vm.expectRevert(MultiOwnerLightAccount.EmptyOwnersNotAllowed.selector);
        account.updateOwners(new address[](0), ownersToRemove);
    }

    function testCannotAddLightContractItselfAsOwner() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(account);
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(MultiOwnerLightAccount.InvalidOwner.selector, (address(account))));
        account.updateOwners(ownersToAdd, new address[](0));
    }

    function testAddAndRemoveSameOwner() public {
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = eoaAddress;
        address[] memory ownersToRemove = new address[](1);
        ownersToRemove[0] = eoaAddress;
        vm.prank(eoaAddress);
        account.updateOwners(ownersToAdd, ownersToRemove);

        address[] memory owners = account.owners();
        assertEq(owners.length, 1);
        assertEq(owners[0], eoaAddress);
    }

    function testRemoveNonexistantOwner() public {
        address[] memory ownersToRemove = new address[](1);
        ownersToRemove[0] = address(0x100);
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(MultiOwnerLightAccount.OwnerDoesNotExist.selector, (address(0x100))));
        account.updateOwners(new address[](0), ownersToRemove);
    }

    function testEntryPointGetter() public {
        assertEq(address(account.entryPoint()), address(entryPoint));
    }

    function testIsValidSignatureForEoaOwner() public {
        bytes32 message = keccak256("hello world");
        bytes memory signature = abi.encodePacked(
            BaseLightAccount.SignatureType.EOA, _sign(EOA_PRIVATE_KEY, _getMessageHash(abi.encode(message)))
        );
        assertEq(account.isValidSignature(message, signature), bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function testIsValidSignatureForContractOwnerSpecified() public {
        _useContractOwner();
        bytes32 message = keccak256("hello world");
        bytes memory signature = abi.encodePacked(
            BaseLightAccount.SignatureType.CONTRACT_WITH_ADDR,
            contractOwner,
            contractOwner.sign(_getMessageHash(abi.encode(message)))
        );
        assertEq(account.isValidSignature(message, signature), bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function testIsValidSignatureRejectsContractOwnerUnspecified() public {
        _useContractOwner();
        bytes32 message = keccak256("hello world");
        bytes memory signature = abi.encodePacked(
            BaseLightAccount.SignatureType.CONTRACT, contractOwner.sign(_getMessageHash(abi.encode(message)))
        );
        vm.expectRevert(abi.encodePacked(BaseLightAccount.InvalidSignatureType.selector));
        account.isValidSignature(message, signature);
    }

    function testIsValidSignatureRejectsInvalidEOA() public {
        bytes32 message = keccak256("hello world");
        bytes memory signature =
            abi.encodePacked(BaseLightAccount.SignatureType.EOA, _sign(123, _getMessageHash(abi.encode(message))));
        assertEq(account.isValidSignature(message, signature), bytes4(0xffffffff));

        // Invalid length
        signature =
            abi.encodePacked(BaseLightAccount.SignatureType.EOA, hex"1234567890abcdef1234567890abcdef1234567890abcdef");
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 24));
        account.isValidSignature(message, signature);

        // 0 length
        signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, hex"");
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 0));
        account.isValidSignature(message, signature);

        // Missing SignatureType prefix
        signature = _sign(EOA_PRIVATE_KEY, _getMessageHash(abi.encode(message)));
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.InvalidSignatureType.selector));
        account.isValidSignature(message, signature);
    }

    function testIsValidSignatureRejectsInvalidContractOwner() public {
        // Signature should fail, because the contract owner is not an owner
        bytes32 message = keccak256("hello world");
        bytes memory signature = abi.encodePacked(
            BaseLightAccount.SignatureType.CONTRACT_WITH_ADDR,
            contractOwner,
            contractOwner.sign(_getMessageHash(abi.encode(message)))
        );
        assertEq(account.isValidSignature(message, signature), bytes4(0xffffffff));
    }

    function testFuzz_isValidSignatureRejectsInvalidSignatureType(uint8 signatureType) public {
        signatureType = uint8(bound(signatureType, 3, type(uint8).max));

        bytes32 message = keccak256("hello world");
        bytes memory signature =
            abi.encodePacked(signatureType, _sign(EOA_PRIVATE_KEY, _getMessageHash(abi.encode(message))));
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.InvalidSignatureType.selector));
        account.isValidSignature(message, signature);
    }

    function testOwnerCanUpgrade() public {
        // Upgrade to a normal SimpleAccount with a different entry point.
        IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
        SimpleAccount newImplementation = new SimpleAccount(newEntryPoint);

        vm.prank(eoaAddress);
        vm.expectEmit(true, true, false, false);
        emit SimpleAccountInitialized(newEntryPoint, address(this));
        account.upgradeToAndCall(address(newImplementation), abi.encodeCall(SimpleAccount.initialize, (address(this))));

        SimpleAccount upgradedAccount = SimpleAccount(payable(account));
        assertEq(address(upgradedAccount.entryPoint()), address(newEntryPoint));
    }

    function testEntryPointCanUpgrade() public {
        // Upgrade to a normal SimpleAccount with a different entry point.
        IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
        SimpleAccount newImplementation = new SimpleAccount(newEntryPoint);
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(
                account.upgradeToAndCall,
                (address(newImplementation), abi.encodeCall(SimpleAccount.initialize, (address(this))))
            ),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.expectEmit(true, true, false, false);
        emit SimpleAccountInitialized(newEntryPoint, address(this));
        entryPoint.handleOps(ops, BENEFICIARY);

        SimpleAccount upgradedAccount = SimpleAccount(payable(account));
        assertEq(address(upgradedAccount.entryPoint()), address(newEntryPoint));
    }

    function testSelfCanUpgrade() public {
        // Upgrade to a normal SimpleAccount with a different entry point.
        IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
        SimpleAccount newImplementation = new SimpleAccount(newEntryPoint);
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(
                BaseLightAccount.execute,
                (
                    address(account),
                    0,
                    abi.encodeCall(
                        account.upgradeToAndCall,
                        (address(newImplementation), abi.encodeCall(SimpleAccount.initialize, (address(this))))
                    )
                )
            ),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.expectEmit(true, true, false, false);
        emit SimpleAccountInitialized(newEntryPoint, address(this));
        entryPoint.handleOps(ops, BENEFICIARY);

        SimpleAccount upgradedAccount = SimpleAccount(payable(account));
        assertEq(address(upgradedAccount.entryPoint()), address(newEntryPoint));
    }

    function testNonOwnerCannotUpgrade() public {
        // Try to upgrade to a normal SimpleAccount with a different entry point.
        IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
        SimpleAccount newImplementation = new SimpleAccount(newEntryPoint);
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, (address(this))));
        account.upgradeToAndCall(address(newImplementation), abi.encodeCall(SimpleAccount.initialize, (address(this))));
    }

    function testStorageSlots() public {
        // No storage at start (slot 0).
        bytes32 storageStart = vm.load(address(account), bytes32(uint256(0)));
        assertEq(storageStart, 0);

        // Instead, storage at the chosen locations.
        bytes32 accountSlot = keccak256(abi.encode(uint256(keccak256("multi_owner_light_account_v1.storage")) - 1))
            & ~bytes32(uint256(0xff));
        address owner = address(bytes20(vm.load(address(account), keccak256(abi.encode(SENTINEL_VALUE, accountSlot)))));
        assertEq(owner, eoaAddress);

        bytes32 initializableSlot = keccak256(
            abi.encode(uint256(keccak256("multi_owner_light_account_v1.initializable")) - 1)
        ) & ~bytes32(uint256(0xff));
        uint8 initialized = abi.decode(abi.encode(vm.load(address(account), initializableSlot)), (uint8));
        assertEq(initialized, 1);
    }

    function testValidateInitCodeHash() external {
        assertEq(
            keccak256(
                abi.encodePacked(
                    type(MultiOwnerLightAccountFactory).creationCode,
                    bytes32(uint256(uint160(0x0000000071727De22E5E9d8BAf0edAc6f37da032)))
                )
            ),
            0x80c58908b2149ff4b21996454a1ad577de59738d9f23637fe3f01506a8836767
        );
    }

    function _useContractOwner() internal {
        vm.prank(eoaAddress);
        address[] memory ownersToAdd = new address[](1);
        ownersToAdd[0] = address(contractOwner);
        address[] memory ownersToRemove = new address[](1);
        ownersToRemove[0] = eoaAddress;
        account.updateOwners(ownersToAdd, ownersToRemove);
    }

    function _getUnsignedOp(bytes memory callData) internal view returns (PackedUserOperation memory) {
        uint128 verificationGasLimit = 1 << 24;
        uint128 callGasLimit = 1 << 24;
        uint128 maxPriorityFeePerGas = 1 << 8;
        uint128 maxFeePerGas = 1 << 8;
        return PackedUserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: 1 << 24,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: "",
            signature: ""
        });
    }

    function _getSignedOp(bytes memory callData, uint256 privateKey)
        internal
        view
        returns (PackedUserOperation memory)
    {
        PackedUserOperation memory op = _getUnsignedOp(callData);
        op.signature = abi.encodePacked(
            BaseLightAccount.SignatureType.EOA, _sign(privateKey, entryPoint.getUserOpHash(op).toEthSignedMessageHash())
        );
        return op;
    }

    function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getStorage(bytes32 position)
        internal
        pure
        returns (MultiOwnerLightAccount.LightAccountStorage storage storageStruct)
    {
        assembly {
            storageStruct.slot := position
        }
    }

    /// @dev Purposefully redefined here to surface any necessary updates to client-side message preparation for
    /// signing, in case `account.getMessageHash()` is updated.
    function _getMessageHash(bytes memory message) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(_MESSAGE_TYPEHASH, keccak256(message)));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    /// @dev Domain separator for the account.
    function _domainSeparator() internal view returns (bytes32) {
        (, string memory name, string memory version,,,,) = account.eip712Domain();
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(account)
            )
        );
    }
}

contract LightSwitch {
    bool public on;

    function turnOn() external payable {
        on = true;
    }
}

contract Reverter {
    function doRevert() external pure {
        revert("did revert");
    }
}

contract Owner is IERC1271 {
    function sign(bytes32 digest) public pure returns (bytes memory) {
        return abi.encodePacked("Signed: ", digest);
    }

    function isValidSignature(bytes32 digest, bytes memory signature) public pure override returns (bytes4) {
        if (keccak256(signature) == keccak256(sign(digest))) {
            return bytes4(keccak256("isValidSignature(bytes32,bytes)"));
        }
        return 0xffffffff;
    }
}
