// SPDX-License-Identifier: MIT

import "SummaryLib.spec";

methods {
    // To fix an issue where immutable variables are not linked in the constructor.
    function _.market(PreLiquidation.Id) external => DISPATCHER(true);
}

// Ensure constructor requirements.

// Base case for mutually dependent invariants.
// Ensure that in a successfully deployed contract the preLLTV value is not zero.
invariant lltvNotZero()
    0 < currentContract.LLTV
    {
        preserved {
            requireInvariant preLIFNotZero();
        }
    }

// Ensure that a successfully deployed contract has a consistent preLLTV value.
invariant preLltvConsistent()
    currentContract.PRE_LLTV < currentContract.LLTV
    {
        preserved {
            requireInvariant preLIFNotZero();
        }
    }

// Ensure that a successfully deployed contract has a consistent preLCF values.
invariant preLCFConsistent()
    currentContract.PRE_LCF_1 <= currentContract.PRE_LCF_2 && currentContract.PRE_LCF_1 <= WAD()
    {
        preserved {
            requireInvariant preLIFNotZero();
        }
    }

// Base case for mutually dependent invariants.
// Ensure that in a successfully deployed contract the preLIF value is not zero.
invariant preLIFNotZero()
    0 < currentContract.PRE_LIF_1;

// Ensure that a successfully deployed contract has a consistent preLIF values.
invariant preLIFConsistent()
    WAD() <= currentContract.PRE_LIF_1 && currentContract.PRE_LIF_1 <= currentContract.PRE_LIF_2 && currentContract.PRE_LIF_2 <= summaryWDivDown(WAD(), currentContract.LLTV)
    {
        preserved {
            requireInvariant lltvNotZero();
        }
    }
