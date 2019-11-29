// from https://github.com/HarryR/ethsnarks/blob/master/contracts/Verifier.sol
pragma solidity 0.5.10;

import "./VerificationKey.sol";

/// @title Verifier Contract
/// @author Matter Labs
contract Verifier is VerificationKey {

    /// @notice If this flag is true - use dummy verification instead of full
    bool constant DUMMY_VERIFIER = false;

    /// @notice Rollup block proof verification
    /// @param _proof Block proof
    /// @param _commitment Block commitment
    function verifyBlockProof(
        uint256[8] calldata _proof,
        bytes32 _commitment
    ) external view returns (bool) {
        uint256 mask = (~uint256(0)) >> 3;
        uint256[14] memory vk;
        uint256[] memory gammaABC;
        (vk, gammaABC) = getVk();
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = uint256(_commitment) & mask;
        return Verify(vk, gammaABC, _proof, inputs);
    }

    /// @notice Verifies exit proof
    /// @param _tokenId Token id
    /// @param _owner Token owner (user)
    /// @param _amount Token amount
    /// @param _proof Proof that user committed
    function verifyExitProof(
        uint16 _tokenId,
        address _owner,
        uint128 _amount,
        uint256[8] calldata _proof
    ) external view returns (bool) {
        bytes32 hash = sha256(
            abi.encodePacked(uint256(_tokenId), uint256(_owner))
        );
        hash = sha256(abi.encodePacked(hash, uint256(_amount)));

        uint256 mask = (~uint256(0)) >> 3;
        uint256[14] memory vk;
        uint256[] memory gammaABC;
        (vk, gammaABC) = getVk();
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = uint256(hash) & mask;
        return Verify(vk, gammaABC, _proof, inputs);
    }

    /// @notice Negates Y value
    /// @param _y Y value
    function NegateY(uint256 _y) internal pure returns (uint256) {
        uint256 q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
        return q - (y % q);
    }

    /// @notice Verifies exit proof
    /// @param _in_vk Verification key inputs
    /// @param _vk_gammaABC Verification key gamma
    /// @param _in_proof Proof input (Block proof)
    /// @param _public_inputs Public inputs (commitment & mask)
    function Verify(
        uint256[14] memory _in_vk,
        uint256[] memory _vk_gammaABC,
        uint256[8] memory _in_proof,
        uint256[] memory _public_inputs
    ) internal view returns (bool) {
        // If DUMMY_VERIFIER constant is true than return true
        if (DUMMY_VERIFIER) {
            return true;
        }

        // Start
        require(
            ((_vk_gammaABC.length / 2) - 1) == _public_inputs.length,
            "vvy11"
        ); // vvy11 - Invalid number of public inputs

        // Compute the linear combination vk_x
        uint256[3] memory mul_input;
        uint256[4] memory add_input;
        bool success;
        uint256 m = 2;

        // First two fields are used as the sum
        add_input[0] = _vk_gammaABC[0];
        add_input[1] = _vk_gammaABC[1];

        // Performs a sum of gammaABC[0] + sum[ gammaABC[i+1]^_public_inputs[i] ]
        for (uint256 i = 0; i < _public_inputs.length; i++) {
            mul_input[0] = _vk_gammaABC[m++];
            mul_input[1] = _vk_gammaABC[m++];
            mul_input[2] = _public_inputs[i];

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // ECMUL, output to last 2 elements of `add_input`
                success := staticcall(
                    sub(gas, 2000),
                    7,
                    mul_input,
                    0x60,
                    add(add_input, 0x40),
                    0x40
                )
            }
            require(
                success,
                "vvy12"
            ); // vvy12 - Failed to call ECMUL precompile

            assembly {
                // ECADD
                success := staticcall(
                    sub(gas, 2000),
                    6,
                    add_input,
                    0x80,
                    add_input,
                    0x40
                )
            }
            require(
                success,
                "vvy13"
            ); // vvy13 - Failed to call ECADD precompile
        }

        uint256[24] memory input = [
            // (proof.A, proof.B)
            _in_proof[0],
            _in_proof[1], // proof.A   (G1)
            _in_proof[2],
            _in_proof[3],
            _in_proof[4],
            _in_proof[5], // proof.B   (G2)
            // (-vk.alpha, vk.beta)
            _in_vk[0],
            NegateY(_in_vk[1]), // -vk.alpha (G1)
            _in_vk[2],
            _in_vk[3],
            _in_vk[4],
            _in_vk[5], // vk.beta   (G2)
            // (-vk_x, vk.gamma)
            add_input[0],
            NegateY(add_input[1]), // -vk_x     (G1)
            _in_vk[6],
            _in_vk[7],
            _in_vk[8],
            _in_vk[9], // vk.gamma  (G2)
            // (-proof.C, vk.delta)
            _in_proof[6],
            NegateY(_in_proof[7]), // -proof.C  (G1)
            _in_vk[10],
            _in_vk[11],
            _in_vk[12],
            _in_vk[13] // vk.delta  (G2)
        ];

        uint256[1] memory out;
        assembly {
            success := staticcall(sub(gas, 2000), 8, input, 768, out, 0x20)
        }
        require(
            success,
            "vvy14"
        ); // vvy14 - Failed to call pairing precompile
        return out[0] == 1;
    }
}