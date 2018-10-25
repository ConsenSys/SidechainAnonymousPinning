/*
 * Copyright 2018 ConsenSys AG.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
 * an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */
pragma solidity ^0.4.23;


/**
 * Contract to manage multiple sidechains.
 *
 * For each sidechain, there are masked and unmasked participants. Unmasked Participants have their
 * addresses listed as being members of a certain sidechain. Being unmasked allows the participant
 * to vote to add and remove other participants, change the voting period and algorithm, and contest
 * pins.
 *
 * Masked Participants are participants which are listed against a sidechain. They are represented
 * as a salted hash of their address. The participant keeps the salt secret and keeps it off-chain.
 * If they need to unmask themselves, they present their secret salt. This is combined with their
 * sending address to create the salted hash. If this matches their masked participant value then
 * they become an unmasked participant.
 *
 * Voting works in the following way:
 * - An Unmasked Participant of a sidechain can submit a proposal for a vote for a certain action
 *  (VOTE_REMOVE_MASKED_PARTICIPANT,VOTE_ADD_UNMASKED_PARTICIPANT, VOTE_REMOVE_UNMASKED_PARTICIPANT,
 *  VOTE_CHANGE_VOTING_ALG, VOTE_CHANGE_VOTING_PERIOD, VOTE_CHANGE_PIN_VOTING_ALG,
 *  VOTE_CHANGE_PIN_VOTING_PERIOD).
 * - Any other Unmasked Participant can then vote on the proposal.
 * - Once the voting period has expired, any Unmasked Participant can request the vote be actioned.
 *
 * The voting algorithm is configurable and set on a per-sidechain basis.
 *
 * Pinning values are put into a map. All participants of a sidechain agree on a sidechain secret.
 * The sidechain secret seeds a Deterministic Random Bit Generator (DRBG). A new 256 bit value is
 * generated each time an uncontested pin is posted. The key in the map is calculated using the
 * equation:
 *
 * DRBG_Value = DRBG.nextValue
 * Key = keccak256(Sidechain Identifier, Previous Pin, DRBG_Value).
 *
 * For the initial key for a sidechain, the Previous Pin is 0x00.
 * The DRBG algorithm needs to be agreed between participants. Algorithms from SP800-90 are known to
 * be good algorithms.
 *
 * Masked and unmasked participants of a sidechain observe the pinning map at the Key value waiting
 * for the next pin to be posted to that entry in the map. When the pin value is posted, they can then
 * determine if they wish to contest the pin. To contest the pin, they submit:
 *
 * Previous Key (and hence the previous pin)
 * DRBG_Value
 * Sidechain Id
 *
 * Given they know the valid DRBG Value, they are able to contest the pin, because they must be a member of the
 * sidechain. Given a good DRBG algorithm, this will not expose future or previous DRBG values, and hence will
 * not reveal earlier or future pinning values, and hence won't reveal the transaction rate of the sidechain.
 *
 * Once a key is revealed as belonging to a specific sidechain, then Unmasked Participants can vote on
 * whether to reject or keep the pin.
 *
 *
 */
interface SidechainAnonPinningInterface {

    /**
     * Add a sidechain to be managed.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @param _votingPeriod The number of blocks by which time a vote must be finalized.
     * @param _votingAlgorithmContract The address of the initial contract to be used for all votes.
     */
    function addSidechain(uint256 _sidechainId, uint64 _votingPeriod, address _votingAlgorithmContract) external;


    /**
     * Convert from being a masked to an unmasked participant. The participant themselves is the only
     * entity which can do this change.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @param _index The index into the list of sidechain masked participants.
     * @return Salted hash or the participant's address, or 0x00.
     */
    function unmask(uint256 _sidechainId, uint256 _index, uint256 _salt) external;

    /**
     * Propose that a certain action be voted on.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @param _participant Either the masked address or the unmasked address (converted to a bytes32) of the entity
     *  to be voted on.
     * @param _action The action to be voted on.
     */
    function proposeVote(uint256 _sidechainId, bytes32 _participant, uint16 _action, uint256 _additionalInfo) external;

    /**
     * Vote for a proposal.
     *
     * If an account has already voted, they can not vote again or change their vote.
     * Only members of the sidechain can vote.
     *
     * @param _participant Either a masked or unmasked participant which the vote pertains to.
     *          If it is an unmasked participant, then the value is an address.
     * @param _action The action to be voted on.
     * @param _voteFor True if the transaction sender wishes to vote for the action.
     */
    function vote(uint256 _sidechainId, bytes32 _participant, uint16 _action, bool _voteFor) external;

    /**
     * Vote for a proposal.
     *
     * If an account has already voted, they can vote again to change their vote.
     * Only members of the sidechain can action votes.
     *
     * @param _participant Either a masked or unmasked participant which the vote pertains to.
     *          If it is an unmasked participant, then the value is an address.
     */
    function actionVotes(uint256 _sidechainId, bytes32 _participant) external;



    /**
     * Add a pin to the pinning map. The key must be calculated based on the equation:
     *
     * Key = keccak256(Sidechain Identifier, Previous Pin, DRBG Value)
     *
     * Where the DRBG Value is the next value to be calculated, based on a shared secret seed
     * off-chain, and the number of values which have been generated.
     *
     *
     * @param _pinKey The pin key calculated as per the equation above.
     * @param _pin Value to be associated with the key.
     */
    function addPin(bytes32 _pinKey, bytes32 _pin) external;


    /**
     * Get the pin value for a certain key. The key must be calculated based on the equation:
     *
     * Key = keccak256(Sidechain Identifier, Previous Pin, DRBG Value)
     *
     * Where the DRBG Value is the next value to be calculated, based on a shared secret seed
     * off-chain, and the number of values which have been generated.
     *
     *
     * @param _pinKey The pin key calculated as per the equation above.
     * @return The pin at the key.
     */
    function getPin(bytes32 _pinKey) external view returns (bytes32);

    /**
     * Contest a pin. The message sender must be an unmasked member of the sidechain,
     * and be able to produce information to demonstrate that the contest pin is part
     * of the sidechain by submitting the previous pin key, the current pin key,
     * and a DRBG value. Given how the keys are created, this proves that the previous
     * and the current key are linked, which proves that the current pin key is part of
     * the sidechain.
     *
     * The keys must be calculated based on the equation:
     *
     * Key = keccak256(Sidechain Identifier, Previous Pin, DRBG Value)
     *
     * Where the DRBG Value is the next value to be calculated, based on a shared secret seed
     * off-chain, and the number of values which have been generated.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @param _previousPinKey The previous pin key calculated as per the equation above.
     * @param _pinKey The pin key calculated as per the equation above.
     * @param _drbgValue The next value in the DRBG sequence.
     */
    function contestPin(uint256 _sidechainId, bytes32 _previousPinKey, bytes32 _pinKey, uint256 _drbgValue) external;



//    function contestPinRequestVote(bytes32 _sidechainId, bytes32 pinKey) external;



    /**
     * Indicate if this contract manages a certain sidechain.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @return true if the sidechain is managed by this contract.
    */
    function getSidechainExists(uint256 _sidechainId) external view returns (bool);

    /**
     * Get the voting period being used in a sidechain.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @return Length of voting period in blocks.
     */
    function getVotingPeriod(uint256 _sidechainId) external view returns (uint64);

    /**
     * Indicate if a certain account is an unmasked participant of a sidechain.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @param _participant Account to check to see if it is a participant.
     * @return true if _participant is an unmasked member of the sidechain.
     */
    function isSidechainParticipant(uint256 _sidechainId, address _participant) external view returns(bool);

    /**
     * Get the number of unmasked sidechain participants for a certain sidechain.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @return number of unmasked sidechain participants.
     */
    function getNumberUnmaskedSidechainParticipants(uint256 _sidechainId) external view returns(uint256);

    /**
     * Get address of a certain unmasked sidechain participant. If the participant has been removed
     * at the given index, this function will return the address 0x00.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @param _index The index into the list of sidechain participants.
     * @return Address of the participant, or 0x00.
     */
    function getUnmaskedSidechainParticipant(uint256 _sidechainId, uint256 _index) external view returns(address);

    /**
     * Get the number of masked sidechain participants for a certain sidechain.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @return number of masked sidechain participants.
     */
    function getNumberMaskedSidechainParticipants(uint256 _sidechainId) external view returns(uint256);

    /*
     * Get the salted hash of a masked sidechain participant. If the participant has been removed
     * or has been unmasked, at the given index, this function will return 0x00.
     *
     * @param _sidechainId The 256 bit identifier of the Sidechain.
     * @param _index The index into the list of sidechain masked participants.
     * @return Salted hash or the participant's address, or 0x00.
     */
    function getMaskedSidechainParticipant(uint256 _sidechainId, uint256 _index) external view returns(bytes32);



    event AddedSidechain(uint256 _sidechainId);
    event AddingSidechainMaskedParticipant(uint256 _sidechainId, bytes32 _participant);
    event AddingSidechainUnmaskedParticipant(uint256 _sidechainId, address _participant);

    event VoteResult(uint256 _sidechainId, bytes32 _participant, uint16 _action, bool _result);


}