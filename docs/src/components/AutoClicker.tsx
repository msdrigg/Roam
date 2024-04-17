import { PropsWithChildren, useEffect, useRef, useState } from "react";

export default function AutoClicker(
    props: PropsWithChildren<{
        href: string;
        preserveQueryParams?: boolean;
    }>
) {
    const clickRef = useRef<HTMLAnchorElement>(null);

    let [url, setUrl] = useState(props.href);

    useEffect(() => {
        if (props.preserveQueryParams) {
            setUrl(props.href + window.location.search);
        } else {
            setUrl(props.href);
        }
    }, [props.href, props.preserveQueryParams]);

    useEffect(() => {
        let timeout = setTimeout(() => {
            if (clickRef.current) {
                clickRef.current.click();
            }
        }, 200);
        return () => {
            clearTimeout(timeout);
        };
    }, [url]);

    return (
        <a ref={clickRef} href={url}>
            {props.children}
        </a>
    );
}
