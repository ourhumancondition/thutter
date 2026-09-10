/// <reference path="../pb_data/types.d.ts" />

// Grants "any signed-in user" access to the collections Thutter syncs.
// Written for PocketBase v0.22 (Dao API). For v0.23+ replace `new Dao(db)` /
// `dao.findCollectionByNameOrId` / `dao.saveCollection` with `app.*`.

const RULE = '@request.auth.id != ""';
const DATA_COLLECTIONS = [
  'contactss',
  'companies',
  'leads',
  'tasks',
  'employees',
  'timelogs',
  'property',
  'workorders',
  'equipment',
];

migrate((db) => {
  const dao = new Dao(db);
  for (const name of DATA_COLLECTIONS) {
    const c = dao.findCollectionByNameOrId(name);
    c.listRule = RULE;
    c.viewRule = RULE;
    c.createRule = RULE;
    c.updateRule = RULE;
    c.deleteRule = RULE;
    dao.saveCollection(c);
  }

  // Tighten workspace writes to the owner.
  const ws = dao.findCollectionByNameOrId('workspace');
  ws.listRule = RULE;
  ws.viewRule = RULE;
  ws.createRule = RULE;
  ws.updateRule = 'owner_id = @request.auth.id';
  ws.deleteRule = 'owner_id = @request.auth.id';
  dao.saveCollection(ws);
}, (db) => {
  const dao = new Dao(db);
  for (const name of [...DATA_COLLECTIONS, 'workspace']) {
    const c = dao.findCollectionByNameOrId(name);
    c.listRule = null;
    c.viewRule = null;
    c.createRule = null;
    c.updateRule = null;
    c.deleteRule = null;
    dao.saveCollection(c);
  }
});
