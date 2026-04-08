"""
ARGUS Universal Dynamic Python Bridge
======================================
Reads JSON-Lines from stdin, dispatches via importlib + getattr,
writes JSON-Lines to stdout.

Zero ARGUS-specific code — works with any Python package.
All language bridges spawn this process and talk to it.

Protocol:
  Request  (one JSON line on stdin)
  Response (one JSON line on stdout)

Request fields:
  id          str      — echoed back (optional)
  session     str      — live object session id (optional)
  module      str      — dotted module path e.g. "argus"
  class       str      — class name (optional)
  init_args   list     — constructor positional args
  init_kwargs dict     — constructor keyword args
  method      str      — method / function to call (optional)
  args        list     — positional args for method
  kwargs      dict     — keyword args for method
  store       bool     — store result in session store
  get_attr    str      — return this attribute of result

Response fields:
  id          str
  session     str
  result      any
  error       str | null
"""

import sys
import json
import importlib
import inspect
import traceback
import uuid

_sessions: dict = {}
_module_cache: dict = {}


def _import_module(module_path: str):
    if module_path not in _module_cache:
        _module_cache[module_path] = importlib.import_module(module_path)
    return _module_cache[module_path]


def _resolve_object(session_id, module: str, class_name):
    if session_id and session_id in _sessions:
        return _sessions[session_id]
    mod = _import_module(module)
    if class_name:
        return getattr(mod, class_name)
    return mod


def _resolve_arg(arg):
    """Session-reference resolution: {"__session__": "id"} -> live Python object."""
    if isinstance(arg, dict) and "__session__" in arg:
        sid = arg["__session__"]
        if sid in _sessions:
            return _sessions[sid]
        raise ValueError(f"Session {sid!r} not found in session store")
    return arg


def _serialize(obj):
    """Recursively convert any Python object to a JSON-serializable form."""
    if obj is None or isinstance(obj, (bool, int, float, str)):
        return obj
    if isinstance(obj, (list, tuple)):
        return [_serialize(i) for i in obj]
    if isinstance(obj, dict):
        return {k: _serialize(v) for k, v in obj.items()}
    if hasattr(obj, "model_dump"):        # Pydantic v2
        try:
            return obj.model_dump()
        except Exception:
            pass
    if hasattr(obj, "dict"):              # Pydantic v1
        try:
            return obj.dict()
        except Exception:
            pass
    if hasattr(obj, "__dataclass_fields__"):
        import dataclasses
        return dataclasses.asdict(obj)
    if hasattr(obj, "value"):             # Enum
        return obj.value
    if hasattr(obj, "__dict__"):
        return {k: _serialize(v) for k, v in obj.__dict__.items()
                if not k.startswith("_")}
    return str(obj)


def _handle(request: dict) -> dict:
    req_id      = request.get("id") or str(uuid.uuid4())
    session_id  = request.get("session")
    module      = request.get("module", "argus")
    class_name  = request.get("class")
    init_args   = request.get("init_args") or []
    init_kwargs = request.get("init_kwargs") or {}
    method      = request.get("method")
    args        = [_resolve_arg(a) for a in (request.get("args") or [])]
    kwargs      = {k: _resolve_arg(v) for k, v in (request.get("kwargs") or {}).items()}
    store       = request.get("store", False)
    get_attr    = request.get("get_attr")

    try:
        target = _resolve_object(session_id, module, class_name)

        if inspect.isclass(target):
            init_args   = [_resolve_arg(a) for a in init_args]
            init_kwargs = {k: _resolve_arg(v) for k, v in init_kwargs.items()}
            instance = target(*init_args, **init_kwargs)
            sid = session_id or str(uuid.uuid4())
            _sessions[sid] = instance
            session_id = sid
            if not method:
                return {"id": req_id, "session": sid, "result": None, "error": None}
            target = instance

        if method:
            fn = getattr(target, method)
            result = fn(*args, **kwargs)
        else:
            result = target

        if get_attr and result is not None:
            result = getattr(result, get_attr)

        new_session_id = session_id
        if store and result is not None and not isinstance(result, (bool, int, float, str, list, dict)):
            sid = str(uuid.uuid4())
            _sessions[sid] = result
            new_session_id = sid
            result = None

        return {"id": req_id, "session": new_session_id,
                "result": _serialize(result), "error": None}

    except Exception as exc:
        return {"id": req_id, "session": session_id,
                "result": None,
                "error": f"{type(exc).__name__}: {exc}\n{traceback.format_exc()}"}


def main():
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            print(json.dumps({"id": None, "session": None, "result": None,
                              "error": f"JSON parse error: {exc}"}), flush=True)
            continue
        print(json.dumps(_handle(request)), flush=True)


if __name__ == "__main__":
    main()
