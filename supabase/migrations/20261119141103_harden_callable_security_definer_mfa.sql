-- Require the same opt-in TOTP assurance level inside every authenticated
-- SECURITY DEFINER RPC. RLS policies do not constrain a SECURITY DEFINER
-- function owned by postgres, so each callable RPC must enforce the MFA gate.
--
-- mfa_access_allowed() permits AAL1 when the user has no verified TOTP factor,
-- and requires AAL2 once the user has a verified factor.

DO $coachingos_mfa_rpc_hardening$
DECLARE
  r record;
  v_definition text;
  v_body text;
  v_new_body text;
  v_transformed text;
  v_count integer := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, l.lanname,
           pg_get_function_result(p.oid) AS result_type
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
  LOOP
    v_definition := pg_get_functiondef(r.oid);

    IF r.lanname = 'plpgsql' THEN
      IF v_definition !~* '\mBEGIN\M' THEN
        RAISE EXCEPTION 'Could not safely locate function body BEGIN for %', r.proname;
      END IF;

      v_transformed := regexp_replace(
        v_definition,
        '(?i)(\mBEGIN\M)',
        '\1' || chr(10) ||
        '  IF NOT coachingos_private.mfa_access_allowed() THEN' || chr(10) ||
        '    RAISE EXCEPTION ''AAL2 MFA verification required'' USING errcode = ''42501'';' || chr(10) ||
        '  END IF;' || chr(10)
      );

    ELSIF r.lanname = 'sql' AND r.result_type = 'boolean' THEN
      v_body := substring(v_definition FROM 'AS \$function\$(.*)\$function\$');
      IF v_body IS NULL THEN
        RAISE EXCEPTION 'Could not extract SQL function body for %', r.proname;
      END IF;
      v_new_body :=
        'BEGIN' || chr(10) ||
        '  IF NOT coachingos_private.mfa_access_allowed() THEN RETURN false; END IF;' || chr(10) ||
        '  RETURN (' || regexp_replace(v_body, ';[[:space:]]*$', '') || ');' || chr(10) ||
        'END;';
      v_transformed := replace(
        replace(v_definition, 'LANGUAGE sql', 'LANGUAGE plpgsql'),
        '$function$' || v_body || '$function$',
        '$function$' || chr(10) || v_new_body || chr(10) || '$function$'
      );

    ELSIF r.lanname = 'sql' AND r.result_type = 'jsonb' THEN
      v_body := substring(v_definition FROM 'AS \$function\$(.*)\$function\$');
      IF v_body IS NULL THEN
        RAISE EXCEPTION 'Could not extract SQL function body for %', r.proname;
      END IF;
      v_new_body :=
        'BEGIN' || chr(10) ||
        '  IF NOT coachingos_private.mfa_access_allowed() THEN RETURN ''[]''::jsonb; END IF;' || chr(10) ||
        '  RETURN (' || regexp_replace(v_body, ';[[:space:]]*$', '') || ');' || chr(10) ||
        'END;';
      v_transformed := replace(
        replace(v_definition, 'LANGUAGE sql', 'LANGUAGE plpgsql'),
        '$function$' || v_body || '$function$',
        '$function$' || chr(10) || v_new_body || chr(10) || '$function$'
      );
    ELSE
      RAISE EXCEPTION 'Unexpected function language or result type for callable SECURITY DEFINER function %: % / %',
        r.proname, r.lanname, r.result_type;
    END IF;

    IF v_transformed = v_definition OR v_transformed IS NULL THEN
      RAISE EXCEPTION 'Failed to transform callable SECURITY DEFINER function %', r.proname;
    END IF;

    EXECUTE v_transformed;
    v_count := v_count + 1;
  END LOOP;

  IF v_count <> 28 THEN
    RAISE EXCEPTION 'Expected to harden 28 callable SECURITY DEFINER functions, hardened %', v_count;
  END IF;
END;
$coachingos_mfa_rpc_hardening$;
