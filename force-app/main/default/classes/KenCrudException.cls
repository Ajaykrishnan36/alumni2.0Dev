/**
 * Raised when the running user lacks the object permission an operation needs.
 *
 * The Apex in this package runs `without sharing` in many places, deliberately:
 * portal members get no record sharing, so enforcing sharing would empty their
 * pages. Object-level CRUD is still checked before every write, and this is what
 * that check throws. Reads are enforced separately, by WITH SYSTEM_MODE on
 * the query itself.
 *
 * The matching object permissions ship in the Alumni* and Ken_* permission sets,
 * so a correctly licensed user never sees this.
 */
public class KenCrudException extends Exception {}