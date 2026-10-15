"""Deploy metabase/dashboards.yml to a Metabase instance through its REST API.

Idempotent: questions are matched by name inside the project collection and updated in
place; each dashboard's layout is replaced with the one in the YAML.

    MB_URL=http://localhost:3000 MB_API_KEY=... MB_DATABASE="GB Grid warehouse" \
        python metabase/deploy.py

    python metabase/deploy.py --plan plan.json   # write the resolved payloads, deploy nothing
"""

import argparse
import json
import os
import pathlib
import sys

import requests
import yaml
from dotenv import load_dotenv

SPEC = pathlib.Path(__file__).with_name("dashboards.yml")
HEATMAP_COLORS = ["#2E9E5B", "#F4D35E", "#D1495B"]  # clean → dirty


def card_payload(card, database_id):
    viz = dict(card.get("viz") or {})
    series = viz.pop("series_colors", None) or {}
    if series:
        settings = viz.setdefault("series_settings", {})
        for name, color in series.items():
            settings.setdefault(name, {})["color"] = color
    if card.get("heatmap_columns"):
        viz["table.column_formatting"] = [{
            "columns": card["heatmap_columns"], "type": "range", "colors": HEATMAP_COLORS,
            "min_type": None, "max_type": None, "highlight_row": False,
        }]
    tags = {
        name: {"id": f"tag-{name}", "name": name, "display-name": t.get("display-name", name),
               "type": t["type"], "default": t.get("default"), "required": t.get("required", False)}
        for name, t in (card.get("tags") or {}).items()
    }
    return {
        "name": card["name"],
        "description": card.get("description"),
        "display": card["display"],
        "visualization_settings": viz,
        "dataset_query": {
            "type": "native", "database": database_id,
            "native": {"query": card["sql"].strip(), "template-tags": tags},
        },
    }


def build_plan(spec, database_id):
    plan = {"collection": spec["collection"], "cards": [], "dashboards": []}
    for dash in spec["dashboards"]:
        params = []
        for p in dash.get("parameters", []):
            param = {"id": p["slug"], "name": p["name"], "slug": p["slug"], "type": p["type"],
                     "default": p.get("default"),
                     "sectionId": "number" if p["type"].startswith("number") else "string"}
            if p.get("values"):  # fixed dropdown instead of a free-text box
                param.update(values_query_type="list", values_source_type="static-list",
                             values_source_config={"values": p["values"]})
            params.append(param)
        dashcards = []
        for card in dash["cards"]:
            col, row, w, h = card["layout"]
            dc = {"col": col, "row": row, "size_x": w, "size_y": h}
            if "text" in card:
                dc.update(card_name=None, visualization_settings={
                    "text": card["text"].strip(),
                    "virtual_card": {"name": None, "display": "text", "visualization_settings": {},
                                     "dataset_query": {}, "archived": False}})
            else:
                plan["cards"].append(card_payload(card, database_id))
                dc.update(card_name=card["name"], visualization_settings={}, parameter_mappings=[
                    {"parameter_id": param, "target": ["variable", ["template-tag", tag]]}
                    for tag, param in (card.get("params") or {}).items()
                ])
            dashcards.append(dc)
        plan["dashboards"].append({"name": dash["name"], "description": dash.get("description"),
                                   "parameters": params, "dashcards": dashcards})
    return plan


class Metabase:
    def __init__(self, url, api_key):
        self.url = url.rstrip("/")
        self.s = requests.Session()
        self.s.headers["x-api-key"] = api_key

    def __call__(self, method, path, body=None):
        r = self.s.request(method, f"{self.url}/api{path}", json=body, timeout=60)
        if r.status_code >= 400:
            sys.exit(f"{method} {path} failed ({r.status_code}): {r.text[:500]}")
        return r.json() if r.content else None


def deploy(mb, plan):
    colls = [c for c in mb("GET", "/collection") if c.get("name") == plan["collection"] and not c.get("archived")]
    coll_id = colls[0]["id"] if colls else mb("POST", "/collection", {"name": plan["collection"]})["id"]

    items = mb("GET", f"/collection/{coll_id}/items?models=card&models=dashboard")["data"]
    existing = {(i["model"], i["name"]): i["id"] for i in items}

    card_ids = {}
    for card in plan["cards"]:
        body = {**card, "collection_id": coll_id}
        if ("card", card["name"]) in existing:
            card_ids[card["name"]] = mb("PUT", f"/card/{existing[('card', card['name'])]}", body)["id"]
        else:
            card_ids[card["name"]] = mb("POST", "/card", body)["id"]

    for dash in plan["dashboards"]:
        dash_id = existing.get(("dashboard", dash["name"])) or mb("POST", "/dashboard", {
            "name": dash["name"], "collection_id": coll_id})["id"]
        dashcards = []
        for i, dc in enumerate(dash["dashcards"]):
            card_id = card_ids.get(dc["card_name"])
            dashcards.append({
                "id": -(i + 1), "card_id": card_id,
                "col": dc["col"], "row": dc["row"], "size_x": dc["size_x"], "size_y": dc["size_y"],
                "visualization_settings": dc["visualization_settings"],
                "parameter_mappings": [{**m, "card_id": card_id} for m in dc.get("parameter_mappings", [])],
            })
        mb("PUT", f"/dashboard/{dash_id}", {"description": dash["description"],
                                             "parameters": dash["parameters"], "dashcards": dashcards})
        print(f"deployed: {dash['name']} → {mb.url}/dashboard/{dash_id}")


def main():
    load_dotenv()
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--plan", help="write the resolved payloads to this file instead of deploying")
    p.add_argument("--database-id", type=int, help="Metabase database id (default: look up MB_DATABASE)")
    args = p.parse_args()
    spec = yaml.safe_load(SPEC.read_text())

    if args.plan:
        plan = build_plan(spec, args.database_id or 0)
        pathlib.Path(args.plan).write_text(json.dumps(plan, indent=2))
        print(f"wrote {args.plan}: {len(plan['cards'])} questions, {len(plan['dashboards'])} dashboards")
        return

    mb = Metabase(os.environ.get("MB_URL", "http://localhost:3000"), os.environ["MB_API_KEY"])
    db_id = args.database_id
    if db_id is None:
        name = os.environ.get("MB_DATABASE", "GB Grid warehouse")
        matches = [d["id"] for d in mb("GET", "/database")["data"] if d["name"] == name]
        if not matches:
            sys.exit(f"No Metabase database named {name!r}; set MB_DATABASE or --database-id")
        db_id = matches[0]
    deploy(mb, build_plan(spec, db_id))


if __name__ == "__main__":
    main()
